"""Live location: the patient chooses to share where they are for a while.

* The patient's phone starts a share, then sends its position every so often.
* Linked caretakers (with the patient's caretaker sharing consent) see the latest
  point in the app; family members get a link to a public map page that only shows
  the latest point of that one share until it stops or expires.
* Only the latest point is stored. Stopping, expiry and erasure delete it.
"""
import html
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import current_user, get_db, patient_for_owner, patient_for_viewer, require_role
from ..models import ROLE_PURPOSE, LiveShare, Link, Patient, User
from .chat import notify_user

router = APIRouter(tags=["live"])
page = APIRouter(tags=["live"])  # the public map page, not under /v1

MAX_MINUTES = 240
LIVE_PUSH_BODY = "Live location was shared with you. Open the app to see it."


class LiveStart(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: float = Field(default=0, ge=0, le=100000)
    minutes: int = Field(default=60, ge=1, le=MAX_MINUTES)


class LivePoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: float = Field(default=0, ge=0, le=100000)


def _own_patient(db: Session, user: User) -> Patient:
    p = db.execute(select(Patient).where(Patient.user_id == user.id)).scalars().first()
    if p is None:
        raise HTTPException(404, "not_found")
    return p


def _active(db: Session, patient_id: str) -> LiveShare | None:
    now = utcnow()
    row = db.execute(select(LiveShare).where(LiveShare.patient_id == patient_id)
                     .order_by(LiveShare.started_at.desc())).scalars().first()
    if row is None:
        return None
    if row.expires_at <= now:
        db.delete(row)
        db.flush()
        return None
    return row


def _base(request: Request) -> str:
    proto = request.headers.get("x-forwarded-proto") or request.url.scheme
    host = request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}"


def _view(row: LiveShare, request: Request) -> dict:
    return {"active": True, "lat": row.lat, "lng": row.lng, "accuracy": row.accuracy,
            "updated_at": row.updated_at.isoformat() + "Z",
            "expires_at": row.expires_at.isoformat() + "Z",
            "url": f"{_base(request)}/live/{row.token}"}


@router.post("/v1/live/start", status_code=201)
def start(body: LiveStart, request: Request,
          user: User = Depends(require_role("patient")), db: Session = Depends(get_db)):
    p = _own_patient(db, user)
    # One share at a time: a new one replaces the old one (and its link stops working).
    db.execute(delete(LiveShare).where(LiveShare.patient_id == p.id))
    # Housekeeping: anything long expired is gone.
    db.execute(delete(LiveShare).where(LiveShare.expires_at < utcnow() - timedelta(days=1)))
    now = utcnow()
    row = LiveShare(token=secrets.token_urlsafe(24), patient_id=p.id,
                    first_name=p.display_name.split(" ")[0][:60], lat=body.lat, lng=body.lng,
                    accuracy=body.accuracy, started_at=now, updated_at=now,
                    expires_at=now + timedelta(minutes=body.minutes))
    db.add(row)
    audit.record(db, user.id, "live_location_started", f"patient={p.id} minutes={body.minutes}")
    links = db.execute(select(Link).where(Link.patient_id == p.id, Link.status == "accepted",
                                          Link.member_role == "caretaker")).scalars().all()
    for ln in links:
        notify_user(request, db, ln.member_user_id, LIVE_PUSH_BODY, data={"type": "location"})
    db.commit()
    return _view(row, request)


@router.put("/v1/live/update")
def update(body: LivePoint, request: Request,
           user: User = Depends(require_role("patient")), db: Session = Depends(get_db)):
    p = _own_patient(db, user)
    row = _active(db, p.id)
    if row is None:
        db.commit()
        raise HTTPException(404, "not_sharing")
    row.lat, row.lng, row.accuracy, row.updated_at = body.lat, body.lng, body.accuracy, utcnow()
    db.commit()
    return _view(row, request)


@router.post("/v1/live/stop", status_code=204)
def stop(user: User = Depends(require_role("patient")), db: Session = Depends(get_db)):
    p = _own_patient(db, user)
    db.execute(delete(LiveShare).where(LiveShare.patient_id == p.id))
    audit.record(db, user.id, "live_location_stopped", f"patient={p.id}")
    db.commit()


@router.get("/v1/live/me")
def mine(request: Request, user: User = Depends(require_role("patient")),
         db: Session = Depends(get_db)):
    """Lets the phone find out whether a share is still running (after a restart)."""
    p = _own_patient(db, user)
    row = _active(db, p.id)
    db.commit()
    return _view(row, request) if row else {"active": False}


@router.get("/v1/live/patient/{patient_id}")
def for_member(patient_id: str, request: Request,
               user: User = Depends(require_role("caretaker")), db: Session = Depends(get_db)):
    """The latest shared point, for a linked caretaker the patient has consented to share with."""
    p, _ = patient_for_viewer(db, user, patient_id)
    row = _active(db, p.id)
    db.commit()
    return _view(row, request) if row else {"active": False}


_STYLE = ("body{margin:0;font-family:system-ui,sans-serif;background:#FAF3EA;color:#0F2A47}"
          ".w{max-width:640px;margin:0 auto;padding:16px}h1{font-size:20px;margin:8px 0}"
          "p{margin:6px 0;color:#4b5563}iframe{width:100%;height:60vh;border:0;border-radius:16px}"
          "a{display:inline-block;margin-top:10px;padding:12px 18px;background:#1B8A4A;"
          "color:#fff;border-radius:14px;text-decoration:none;font-weight:600}")


@page.get("/live/{token}", response_class=HTMLResponse)
def public_page(token: str, db: Session = Depends(get_db)):
    row = db.get(LiveShare, token) if 8 <= len(token) <= 48 else None
    headers = {"Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
               "X-Robots-Tag": "noindex, nofollow"}
    if row is None or row.expires_at <= utcnow():
        body = (f"<!doctype html><meta charset=utf-8><meta name=viewport "
                f"content='width=device-width,initial-scale=1'><title>Live location</title>"
                f"<style>{_STYLE}</style><div class=w><h1>This live location has ended</h1>"
                f"<p>The person stopped sharing, or the time ran out.</p></div>")
        return HTMLResponse(body, status_code=404, headers=headers)
    d = 0.004
    bbox = f"{row.lng - d},{row.lat - d},{row.lng + d},{row.lat + d}"
    osm = (f"https://www.openstreetmap.org/export/embed.html?bbox={bbox}"
           f"&layer=mapnik&marker={row.lat},{row.lng}")
    gmaps = f"https://www.google.com/maps?q={row.lat},{row.lng}"
    name = html.escape(row.first_name or "Someone")
    age = max(0, int((utcnow() - row.updated_at).total_seconds() // 60))
    until = row.expires_at.strftime("%H:%M UTC")
    body = (f"<!doctype html><meta charset=utf-8><meta name=viewport "
            f"content='width=device-width,initial-scale=1'><meta http-equiv=refresh content=30>"
            f"<title>Live location</title><style>{_STYLE}</style><div class=w>"
            f"<h1>{name} is sharing a live location</h1>"
            f"<p>Updated {age} min ago. Sharing until {until}. This page refreshes by itself.</p>"
            f"<iframe src='{html.escape(osm)}' loading=lazy></iframe>"
            f"<a href='{html.escape(gmaps)}'>Open in Maps</a></div>")
    return HTMLResponse(body, headers=headers)
