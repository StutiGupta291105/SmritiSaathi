"""Admin portal API. READ ONLY.

There is exactly one admin, with a fixed username and password set in the server's
settings (SMRITI_ADMIN_USERNAME / SMRITI_ADMIN_PASSWORD or _HASH). It is not a user
account: it is not in the users table, the mobile app knows nothing of it, and no API
can create, change or list admins. With no password configured these routes do not exist.

Every endpoint here is a GET, apart from the sign-in itself. Nothing in this file
changes patients, caretakers, doctors, links, consents, reminders or messages, and
a test fails if a writing route is ever added. The portal is for monitoring: who is
in the system, who supervises whom, and what happened (the access log).

It shows what the server holds, and no more: names, roles, ids, the last four phone
digits, links, consent state, counts and the audit log. It never returns chat
messages, photos, voice notes, reminder titles or game answers, which the product
promises to keep between the people involved. Admin sign-ins and the views of a
person's page are themselves written to the audit log."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import current_admin, get_db, ip_hash, settings_of
from ..models import (CONSENT_PURPOSES, AuditEntry, CareReminder, Consent,
                      DeviceToken, GameSession, Link, Message, Patient, User)
from ..security import admin_password_ok, make_admin_token, totp_ok

router = APIRouter(prefix="/v1/admin", tags=["admin"])

LOCK_AFTER, LOCK_MINUTES = 5, 15
LOGIN_ACTIONS = ("login", "signup")
ADMIN_ACTOR = "admin"


class AdminLogin(BaseModel):
    username: str
    password: str
    code: str = ""


@router.post("/login")
def login(body: AdminLogin, request: Request, db: Session = Depends(get_db)):
    """The one fixed admin account from the server settings. Password, plus the
    authenticator code when a secret is configured. Five wrong tries from one address
    lock that address for 15 minutes (counted from the audit log, so it survives
    restarts and works across instances)."""
    s = settings_of(request)
    ip = ip_hash(request)[:12]
    since = utcnow() - timedelta(minutes=LOCK_MINUTES)
    recent = db.execute(select(func.count(AuditEntry.id)).where(
        AuditEntry.action == "admin_login_failed", AuditEntry.ts >= since,
        AuditEntry.detail == f"ip={ip}")).scalar_one()
    if recent >= LOCK_AFTER:
        raise HTTPException(429, "locked")
    ok = (body.username.strip().lower() == s.admin_username and admin_password_ok(body.password, s)
          and (not s.admin_totp_secret or totp_ok(s.admin_totp_secret, body.code)))
    if not ok:
        audit.record(db, "system", "admin_login_failed", f"ip={ip}")
        db.commit()
        raise HTTPException(401, "invalid_credentials")
    audit.record(db, ADMIN_ACTOR, "admin_login", f"ip={ip}")
    return {"access_token": make_admin_token(s.admin_username, s),
            "username": s.admin_username, "expires_in": 1800}


# ---- helpers ------------------------------------------------------------------

def _iso(dt):
    return dt.isoformat() if dt else None


def _consents(db: Session, pid: str) -> dict:
    """Current state per purpose: newest row wins."""
    out = {p: {"granted": False, "at": None, "by": None} for p in CONSENT_PURPOSES}
    for c in db.execute(select(Consent).where(Consent.patient_id == pid)
                        .order_by(Consent.id)).scalars():
        out[c.purpose] = {"granted": c.granted, "at": _iso(c.created_at),
                          "by": f"{c.given_by_name} ({c.given_by_relation})"}
    return out


def _last_logins(db: Session, ids: list[str]) -> dict:
    if not ids:
        return {}
    rows = db.execute(select(AuditEntry.actor, func.max(AuditEntry.ts)).where(
        AuditEntry.actor.in_(ids), AuditEntry.action.in_(LOGIN_ACTIONS))
        .group_by(AuditEntry.actor)).all()
    return {a: _iso(t) for a, t in rows}


def _link_row(l: Link, patient: Patient, member: User | None, msgs: dict) -> dict:
    n, last = msgs.get(l.id, (0, None))
    return {
        "id": l.id, "status": l.status, "member_role": l.member_role,
        "patient_id": patient.id, "patient_user_id": patient.user_id, "patient_name": patient.display_name,
        "member_user_id": member.id if member else None,
        "member_name": member.name if member else l.invitee_name,
        "member_care_id": member.care_id if member else l.invitee_care_id,
        "member_verified": bool(member and member.verified_at),
        "invited_name": l.invitee_name, "professional_id": l.professional_id or None,
        "created_at": _iso(l.created_at), "updated_at": _iso(l.updated_at),
        "message_count": n, "last_message_at": _iso(last),
    }


def _msg_stats(db: Session) -> dict:
    return {lid: (n, t) for lid, n, t in db.execute(
        select(Message.link_id, func.count(Message.id), func.max(Message.created_at))
        .group_by(Message.link_id)).all()}


def _page(q, limit, offset):
    return q.limit(limit).offset(offset)


# ---- overview -----------------------------------------------------------------

@router.get("/overview")
def overview(admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    day = utcnow() - timedelta(hours=24)
    cnt = lambda q: db.execute(q).scalar_one()
    roles = {r: cnt(select(func.count(User.id)).where(User.role == r))
             for r in ("patient", "doctor", "caretaker")}
    links = {st: cnt(select(func.count(Link.id)).where(Link.status == st))
             for st in ("pending", "accepted", "declined", "revoked")}
    act = lambda a: cnt(select(func.count(AuditEntry.id)).where(
        AuditEntry.action == a, AuditEntry.ts >= day))
    return {
        "users": roles,
        "doctors_unverified": cnt(select(func.count(User.id)).where(
            User.role == "doctor", User.verified_at.is_(None))),
        "links": links,
        "patients_without_supervisor": cnt(select(func.count(Patient.id)).where(
            ~Patient.id.in_(select(Link.patient_id).where(Link.status == "accepted")))),
        "sessions_24h": cnt(select(func.count(GameSession.id)).where(GameSession.ended_at >= day)),
        "messages_24h": cnt(select(func.count(Message.id)).where(Message.created_at >= day)),
        "care_reminders": cnt(select(func.count(CareReminder.id)).where(CareReminder.deleted.is_(False))),
        "devices": cnt(select(func.count(DeviceToken.id))),
        "logins_24h": act("login") + act("signup"),
        "otp_failed_24h": act("otp_failed"),
        "access_denied_24h": act("access_denied"),
        "refresh_reuse_24h": act("refresh_reuse_detected"),
        "admin_logins_24h": act("admin_login"),
        "audit_entries": cnt(select(func.count(AuditEntry.id))),
    }


# ---- people -------------------------------------------------------------------

def _user_item(u: User, logins: dict, extra: dict) -> dict:
    return {"id": u.id, "role": u.role, "name": u.name, "phone_last4": u.phone_last4,
            "care_id": u.care_id, "verified": bool(u.verified_at),
            "created_at": _iso(u.created_at), "last_login_at": logins.get(u.id), **extra}


@router.get("/users")
def users(role: str = "", q: str = "", limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0),
          admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    cond = []
    if role:
        cond.append(User.role == role)
    if q.strip():
        like = f"%{q.strip()}%"
        cond.append(or_(User.name.ilike(like), User.care_id.ilike(like),
                        User.phone_last4 == q.strip(), User.id.startswith(q.strip())))
    base = select(User).where(and_(*cond)) if cond else select(User)
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = db.execute(_page(base.order_by(User.created_at.desc()), limit, offset)).scalars().all()
    logins = _last_logins(db, [u.id for u in rows])
    accepted = dict(db.execute(select(Link.member_user_id, func.count(Link.id)).where(
        Link.status == "accepted", Link.member_user_id.in_([u.id for u in rows]))
        .group_by(Link.member_user_id)).all())
    items = [_user_item(u, logins, {"patients": accepted.get(u.id, 0)} if u.role != "patient" else {})
             for u in rows]
    return {"total": total, "items": items}


@router.get("/patients")
def patients(q: str = "", limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0),
             admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    base = select(Patient, User).join(User, User.id == Patient.user_id)
    if q.strip():
        like = f"%{q.strip()}%"
        base = base.where(or_(Patient.display_name.ilike(like), User.phone_last4 == q.strip(),
                              Patient.id.startswith(q.strip()), User.id.startswith(q.strip())))
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = db.execute(_page(base.order_by(Patient.created_at.desc()), limit, offset)).all()
    pids = [p.id for p, _ in rows]
    team: dict[str, list] = {}
    for l, m in db.execute(select(Link, User).outerjoin(User, User.id == Link.member_user_id)
                           .where(Link.patient_id.in_(pids), Link.status == "accepted")):
        team.setdefault(l.patient_id, []).append(
            {"role": l.member_role, "name": m.name if m else l.invitee_name,
             "user_id": m.id if m else None})
    games = {pid: (n, t) for pid, n, t in db.execute(
        select(GameSession.patient_id, func.count(GameSession.id), func.max(GameSession.ended_at))
        .where(GameSession.patient_id.in_(pids)).group_by(GameSession.patient_id)).all()}
    items = []
    for p, u in rows:
        c = _consents(db, p.id)
        n, last = games.get(p.id, (0, None))
        items.append({
            "patient_id": p.id, "user_id": u.id, "name": p.display_name, "phone_last4": u.phone_last4,
            "language": p.language, "baseline_level": p.baseline_level,
            "created_at": _iso(p.created_at),
            "caregivers": [x for x in team.get(p.id, []) if x["role"] == "caretaker"],
            "doctors": [x for x in team.get(p.id, []) if x["role"] == "doctor"],
            "sharing": {"caregiver": c["caregiver_share"]["granted"], "doctor": c["doctor_share"]["granted"],
                        "sync": c["sync"]["granted"], "companion": c["companion"]["granted"]},
            "sessions": n, "last_played": _iso(last)})
    return {"total": total, "items": items}


@router.get("/users/{user_id}")
def user_detail(user_id: str, admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    u = db.get(User, user_id)
    if u is None:
        raise HTTPException(404, "not_found")
    audit.record(db, ADMIN_ACTOR, "admin_viewed_user", f"user={u.id}")
    msgs = _msg_stats(db)
    out = {"user": _user_item(u, _last_logins(db, [u.id]), {}),
           "devices": db.execute(select(func.count(DeviceToken.id)).where(
               DeviceToken.user_id == u.id)).scalar_one(),
           "contact_phone_shared": bool(u.contact_phone)}
    if u.role == "patient":
        p = db.execute(select(Patient).where(Patient.user_id == u.id)).scalar_one_or_none()
        if p:
            links = db.execute(select(Link).where(Link.patient_id == p.id)
                               .order_by(Link.created_at)).scalars().all()
            members = {m.id: m for m in db.execute(select(User).where(User.id.in_(
                [l.member_user_id for l in links if l.member_user_id]))).scalars()}
            n, last = db.execute(select(func.count(GameSession.id), func.max(GameSession.ended_at))
                                 .where(GameSession.patient_id == p.id)).one()
            out["patient"] = {
                "patient_id": p.id, "name": p.display_name, "language": p.language,
                "baseline_level": p.baseline_level, "tz_offset_minutes": p.tz_offset_minutes,
                "created_at": _iso(p.created_at), "sessions": n, "last_played": _iso(last),
                "care_reminders": db.execute(select(func.count(CareReminder.id)).where(
                    CareReminder.patient_id == p.id, CareReminder.deleted.is_(False))).scalar_one(),
                "consents": _consents(db, p.id),
                "consent_changes": db.execute(select(func.count(Consent.id)).where(
                    Consent.patient_id == p.id)).scalar_one()}
            out["supervisors"] = [_link_row(l, p, members.get(l.member_user_id), msgs) for l in links]
    else:
        links = db.execute(select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
                           .where(Link.member_user_id == u.id).order_by(Link.created_at)).all()
        out["patients"] = [_link_row(l, p, u, msgs) for l, p in links]
        pend = [Link.member_user_id == u.id]
        if u.care_id:
            pend.append(Link.invitee_care_id == u.care_id)
        out["pending_invites"] = db.execute(select(func.count(Link.id)).where(
            Link.status == "pending", or_(*pend))).scalar_one()
        out["care_reminders_set"] = db.execute(select(func.count(CareReminder.id)).where(
            CareReminder.created_by == u.id)).scalar_one()
        out["messages_sent"] = db.execute(select(func.count(Message.id)).where(
            Message.sender_id == u.id)).scalar_one()
    cond = [AuditEntry.actor == u.id]
    if u.role == "patient" and "patient" in out:
        cond.append(AuditEntry.detail.contains(f"patient={out['patient']['patient_id']}"))
    recent = db.execute(select(AuditEntry).where(or_(*cond)).order_by(AuditEntry.id.desc()).limit(40)).scalars()
    out["recent_activity"] = [_audit_item(e, {}) for e in recent]
    return out


# ---- who supervises whom --------------------------------------------------------

@router.get("/links")
def links(status: str = "", role: str = "", q: str = "", limit: int = Query(100, ge=1, le=500),
          offset: int = Query(0, ge=0), admin: str = Depends(current_admin),
          db: Session = Depends(get_db)):
    base = select(Link, Patient, User).join(Patient, Patient.id == Link.patient_id).outerjoin(
        User, User.id == Link.member_user_id)
    if status:
        base = base.where(Link.status == status)
    if role:
        base = base.where(Link.member_role == role)
    if q.strip():
        like = f"%{q.strip()}%"
        base = base.where(or_(Patient.display_name.ilike(like), Link.invitee_name.ilike(like),
                              User.name.ilike(like), Link.invitee_care_id.ilike(like)))
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = db.execute(_page(base.order_by(Link.updated_at.desc()), limit, offset)).all()
    msgs = _msg_stats(db)
    return {"total": total, "items": [_link_row(l, p, m, msgs) for l, p, m in rows]}


# ---- audit / access log -----------------------------------------------------------

def _audit_item(e: AuditEntry, names: dict) -> dict:
    who = e.actor
    return {"id": e.id, "ts": _iso(e.ts), "actor": who, "actor_name": names.get(who),
            "action": e.action, "detail": e.detail, "hash": e.hash[:16]}


def _names(db: Session, entries) -> dict:
    ids = {e.actor for e in entries if len(e.actor) == 36}
    return {u.id: f"{u.name} ({u.role})" for u in db.execute(
        select(User).where(User.id.in_(ids))).scalars()} if ids else {}


@router.get("/audit")
def audit_log(actor: str = "", action: str = "", q: str = "", since_hours: int = Query(0, ge=0, le=24 * 365),
              limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0),
              admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    cond = []
    if actor:
        cond.append(AuditEntry.actor == actor)
    if action:
        cond.append(AuditEntry.action == action)
    if q.strip():
        cond.append(AuditEntry.detail.contains(q.strip()))
    if since_hours:
        cond.append(AuditEntry.ts >= utcnow() - timedelta(hours=since_hours))
    base = select(AuditEntry).where(and_(*cond)) if cond else select(AuditEntry)
    total = db.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = db.execute(_page(base.order_by(AuditEntry.id.desc()), limit, offset)).scalars().all()
    names = _names(db, rows)
    return {"total": total, "items": [_audit_item(e, names) for e in rows],
            "actions": sorted(a for (a,) in db.execute(select(AuditEntry.action).distinct()).all())}


@router.get("/audit/verify")
def audit_verify(admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    return {"ok": audit.verify_chain(db), "head": audit.head_hash(db),
            "entries": db.execute(select(func.count(AuditEntry.id))).scalar_one()}


SECURITY_ACTIONS = ("otp_failed", "access_denied", "refresh_reuse_detected", "admin_login_failed",
                    "links_revoked", "link_revoked", "patient_erased", "patient_exported",
                    "doctor_verified", "doctor_unverified", "consent_recorded")


@router.get("/security")
def security(admin: str = Depends(current_admin), db: Session = Depends(get_db)):
    """What a security review looks at first."""
    day = utcnow() - timedelta(hours=24)
    week = utcnow() - timedelta(days=7)
    cnt = lambda a, since: db.execute(select(func.count(AuditEntry.id)).where(
        AuditEntry.action == a, AuditEntry.ts >= since)).scalar_one()
    recent = db.execute(select(AuditEntry).where(AuditEntry.action.in_(SECURITY_ACTIONS))
                        .order_by(AuditEntry.id.desc()).limit(100)).scalars().all()
    names = _names(db, recent)
    top = db.execute(select(AuditEntry.actor, func.count(AuditEntry.id)).where(
        AuditEntry.action == "report_viewed", AuditEntry.ts >= week)
        .group_by(AuditEntry.actor).order_by(func.count(AuditEntry.id).desc()).limit(10)).all()
    tn = {u.id: f"{u.name} ({u.role})" for u in db.execute(
        select(User).where(User.id.in_([a for a, _ in top]))).scalars()} if top else {}
    return {
        "last_24h": {a: cnt(a, day) for a in ("otp_failed", "access_denied", "refresh_reuse_detected",
                                              "admin_login_failed", "login", "report_viewed")},
        "last_7d": {a: cnt(a, week) for a in ("access_denied", "consent_recorded", "patient_erased",
                                              "patient_exported", "links_revoked", "link_revoked")},
        "doctors_unverified": [{"id": u.id, "name": u.name, "care_id": u.care_id, "created_at": _iso(u.created_at)}
                               for u in db.execute(select(User).where(
                                   User.role == "doctor", User.verified_at.is_(None))).scalars()],
        "top_report_viewers_7d": [{"actor": a, "name": tn.get(a), "views": n} for a, n in top],
        "recent_events": [_audit_item(e, names) for e in recent],
    }
