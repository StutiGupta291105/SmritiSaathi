from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import analytics, audit
from ..db import utcnow
from ..deps import (consent_granted, current_user, get_db, patient_for_viewer,
                    require_role)
from ..models import (ROLE_PURPOSE, GameSession, Link, Patient, ReminderMark,
                      ReminderSchedule, User)
from ..schemas import InviteForMe

router = APIRouter(prefix="/v1", tags=["care"])


# ---- invites (caretaker / doctor side) ---------------------------------------------

def _pending_for(db: Session, user: User) -> list[tuple[Link, Patient]]:
    rows = db.execute(
        select(Link, Patient).join(Patient, Patient.id == Link.patient_id).where(
            Link.invitee_phone_hmac == user.phone_hmac,
            Link.member_role == user.role,
            Link.status == "pending",
        ).order_by(Link.created_at)
    ).all()
    purpose = ROLE_PURPOSE[user.role]
    return [(l, p) for l, p in rows if consent_granted(db, p.id, purpose)]


@router.get("/invites", response_model=list[InviteForMe])
def my_invites(user: User = Depends(require_role("caretaker", "doctor")),
               db: Session = Depends(get_db)):
    return [InviteForMe(id=l.id, patient_display_name=p.display_name,
                        member_role=l.member_role, created_at=l.created_at)
            for l, p in _pending_for(db, user)]


def _my_pending_invite(db: Session, user: User, invite_id: str) -> Link:
    for l, _ in _pending_for(db, user):
        if l.id == invite_id:
            return l
    raise HTTPException(404, "not_found")


@router.post("/invites/{invite_id}/accept")
def accept(invite_id: str, user: User = Depends(require_role("caretaker", "doctor")),
           db: Session = Depends(get_db)):
    link = _my_pending_invite(db, user, invite_id)
    link.status, link.member_user_id, link.updated_at = "accepted", user.id, utcnow()
    audit.record(db, user.id, "invite_accepted", f"link={link.id} patient={link.patient_id}")
    return {"status": "accepted", "patient_id": link.patient_id}


@router.post("/invites/{invite_id}/decline")
def decline(invite_id: str, user: User = Depends(require_role("caretaker", "doctor")),
            db: Session = Depends(get_db)):
    link = _my_pending_invite(db, user, invite_id)
    link.status, link.updated_at = "declined", utcnow()
    audit.record(db, user.id, "invite_declined", f"link={link.id} patient={link.patient_id}")
    return {"status": "declined"}


@router.delete("/links/{link_id}", status_code=204)
def revoke(link_id: str, user: User = Depends(current_user),
           db: Session = Depends(get_db)):
    """Either side can end a link: the patient (who owns the data) or the
    caretaker/doctor (who no longer wants access)."""
    link = db.get(Link, link_id)
    if link is None:
        raise HTTPException(404, "not_found")
    patient = db.get(Patient, link.patient_id)
    is_owner = user.role == "patient" and patient.user_id == user.id
    is_member = link.member_user_id == user.id
    if not (is_owner or is_member):
        raise HTTPException(404, "not_found")
    if link.status in ("pending", "accepted"):
        link.status, link.updated_at = "revoked", utcnow()
        audit.record(db, user.id, "link_revoked", f"link={link.id} patient={link.patient_id}")


# ---- reports and alerts ---------------------------------------------------------------

def build_report(db: Session, p: Patient, days: int) -> dict:
    off = timedelta(minutes=p.tz_offset_minutes)
    now_local = utcnow() + off
    since = utcnow() - timedelta(days=400)

    sessions = [analytics.Sess(
        game=s.game, ended_at=s.ended_at + off, start_level=s.start_level,
        end_level=s.end_level, trials=s.trials, correct=s.correct)
        for s in db.execute(select(GameSession).where(
            GameSession.patient_id == p.id, GameSession.ended_at >= since)).scalars()]
    rems = [analytics.Rem(
        id=r.id, kind=r.kind, hour=r.hour, minute=r.minute, days_mask=r.days_mask,
        on_date=date.fromisoformat(r.on_date) if r.on_date else None,
        active=r.active, created_at=r.created_at + off)
        for r in db.execute(select(ReminderSchedule).where(
            ReminderSchedule.patient_id == p.id)).scalars()]
    done = {(m.reminder_id, m.day) for m in db.execute(
        select(ReminderMark).where(ReminderMark.patient_id == p.id)).scalars()}

    week = analytics.adherence(rems, done, now_local, 7)
    alerts = analytics.compute_alerts(
        sessions, now_local, p.baseline_level,
        overdue=analytics.overdue_medicines(rems, done, now_local), week=week)
    in_range = analytics.sessions_in_range(sessions, now_local, days)
    played_days = {s.ended_at.date() for s in sessions}
    last = max((s.ended_at for s in sessions), default=None)
    return {
        "patient": {"id": p.id, "display_name": p.display_name,
                    "baseline_level": p.baseline_level},
        "range_days": days,
        "games_played": len(in_range),
        "streak": analytics.current_streak(played_days, now_local.date()),
        "last_played": last.isoformat() if last else None,
        "daily": analytics.buckets(sessions, now_local, days),
        "per_game": analytics.per_game(in_range),
        "adherence": {"expected": week[0], "done": week[1]},
        "alerts": [{"kind": a.kind, "severity": a.severity, "a": a.a, "b": a.b}
                   for a in alerts],
    }


@router.get("/patients/{patient_id}/report")
def report(patient_id: str, request: Request,
           days: int = Query(7, description="7, 30 or 90"),
           user: User = Depends(current_user), db: Session = Depends(get_db)):
    """For the patient, or a linked caretaker/doctor whose link is accepted and
    for whom the patient's sharing consent is currently granted. Reads by
    others are written to the audit log (DPDP: who saw what)."""
    if days not in (7, 30, 90):
        raise HTTPException(422, "days_must_be_7_30_or_90")
    p, kind = patient_for_viewer(db, user, patient_id)
    if kind == "member":
        audit.record(db, user.id, "report_viewed", f"patient={p.id} days={days}")
    return build_report(db, p, days)


@router.get("/my-patients")
def my_patients(user: User = Depends(require_role("caretaker", "doctor")),
                db: Session = Depends(get_db)):
    """Patients this caretaker or doctor may see right now, with how many
    alerts need attention."""
    purpose = ROLE_PURPOSE[user.role]
    rows = db.execute(
        select(Link, Patient).join(Patient, Patient.id == Link.patient_id).where(
            Link.member_user_id == user.id, Link.member_role == user.role,
            Link.status == "accepted")
    ).all()
    out = []
    for link, p in rows:
        if not consent_granted(db, p.id, purpose):
            continue
        rep = build_report(db, p, 7)
        out.append({
            "patient_id": p.id, "display_name": p.display_name,
            "link_role": link.member_role,
            "alerts_needing_attention": sum(
                1 for a in rep["alerts"] if a["severity"] == "attention"),
        })
    return out
