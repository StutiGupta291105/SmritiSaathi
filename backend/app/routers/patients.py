from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import (consent_granted, current_user, get_db, patient_for_owner,
                    patient_for_viewer, require_role, settings_of)
from ..models import (CONSENT_PURPOSES, ROLE_PURPOSE, Consent, GameSession,
                      Link, OtpChallenge, Patient, RefreshToken,
                      ReminderMark, ReminderSchedule, User)
from ..schemas import (BaselineIn, ConsentsIn, InviteIn, LinkOut, PatientIn,
                       PatientOut, SyncIn, SyncOut)
from ..security import clean_care_id, normalize_phone, phone_hmac, role_of_care_id

router = APIRouter(prefix="/v1/patients", tags=["patients"])


def _out(p: Patient) -> PatientOut:
    return PatientOut(id=p.id, display_name=p.display_name, language=p.language,
                      baseline_level=p.baseline_level,
                      tz_offset_minutes=p.tz_offset_minutes)


def naive_utc(dt: datetime) -> datetime:
    return dt.astimezone(timezone.utc).replace(tzinfo=None) if dt.tzinfo else dt


def _link_out(l: Link, db: Session) -> LinkOut:
    member = db.get(User, l.member_user_id) if l.member_user_id else None
    return LinkOut(verified=bool(member and member.verified_at), id=l.id, patient_id=l.patient_id, member_role=l.member_role,
                   invitee_name=l.invitee_name, professional_id=l.professional_id,
                   status=l.status, created_at=l.created_at)


# ---- profile -----------------------------------------------------------------

@router.post("", response_model=PatientOut, status_code=201)
def create_patient(body: PatientIn, user: User = Depends(require_role("patient")),
                   db: Session = Depends(get_db)):
    if db.execute(select(Patient).where(Patient.user_id == user.id)).scalar_one_or_none():
        raise HTTPException(409, "patient_exists")
    p = Patient(user_id=user.id, display_name=body.display_name.strip(),
                language=body.language, baseline_level=body.baseline_level,
                tz_offset_minutes=body.tz_offset_minutes)
    db.add(p)
    db.flush()
    audit.record(db, user.id, "patient_created", f"patient={p.id}")
    return _out(p)


@router.get("/me", response_model=PatientOut)
def my_patient(user: User = Depends(require_role("patient")),
               db: Session = Depends(get_db)):
    p = db.execute(select(Patient).where(Patient.user_id == user.id)).scalar_one_or_none()
    if p is None:
        raise HTTPException(404, "not_found")
    return _out(p)


@router.patch("/{patient_id}/baseline", response_model=PatientOut)
def set_baseline(patient_id: str, body: BaselineIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    """The patient, or an accepted caretaker, sets the starting level."""
    p, kind = patient_for_viewer(db, user, patient_id)
    if kind == "member" and user.role != "caretaker":
        raise HTTPException(403, "wrong_role")
    old = p.baseline_level
    p.baseline_level = body.baseline_level
    audit.record(db, user.id, "baseline_changed",
                 f"patient={p.id} {old}->{body.baseline_level}")
    return _out(p)


# ---- consent -------------------------------------------------------------------

def _consent_state(db: Session, patient_id: str) -> dict[str, bool]:
    return {purpose: consent_granted(db, patient_id, purpose)
            for purpose in CONSENT_PURPOSES}


@router.post("/{patient_id}/consents", status_code=201)
def add_consents(patient_id: str, body: ConsentsIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    """Appends decisions to the consent log (never edits it). Withdrawing a
    sharing purpose ends the matching doctor or caretaker links at once."""
    p = patient_for_owner(db, user, patient_id)
    for c in body.consents:
        db.add(Consent(patient_id=p.id, purpose=c.purpose, granted=c.granted,
                       given_by_name=c.given_by_name, given_by_relation=c.given_by_relation,
                       notice_version=c.notice_version))
        audit.record(db, user.id, "consent_recorded",
                     f"patient={p.id} purpose={c.purpose} granted={c.granted}")
        if not c.granted:
            for role, purpose in ROLE_PURPOSE.items():
                if purpose == c.purpose:
                    db.execute(update(Link).where(
                        Link.patient_id == p.id, Link.member_role == role,
                        Link.status.in_(("pending", "accepted")),
                    ).values(status="revoked", updated_at=utcnow()))
                    audit.record(db, user.id, "links_revoked", f"patient={p.id} role={role}")
    db.flush()
    return _consent_state(db, p.id)


@router.get("/{patient_id}/consents")
def get_consents(patient_id: str, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    p = patient_for_owner(db, user, patient_id)
    return _consent_state(db, p.id)


# ---- invites (patient side) -----------------------------------------------------

@router.post("/{patient_id}/invites", response_model=LinkOut, status_code=201)
def invite(patient_id: str, body: InviteIn, request: Request,
           user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = patient_for_owner(db, user, patient_id)
    if not consent_granted(db, p.id, ROLE_PURPOSE[body.role]):
        raise HTTPException(403, "consent_required")
    care_id = clean_care_id(body.care_id) if body.care_id.strip() else None
    if body.care_id.strip() and care_id is None:
        raise HTTPException(422, "invalid_care_id")
    if care_id:
        if role_of_care_id(care_id) != body.role:
            raise HTTPException(422, "care_id_wrong_role")
        # IDs are random and the answer is rate limited like everything else.
        if db.scalar(select(User.id).where(User.care_id == care_id,
                                           User.role == body.role)) is None:
            raise HTTPException(404, "care_id_not_found")
        ph, who = "", Link.invitee_care_id == care_id
    else:
        phone = normalize_phone(body.phone)
        if phone is None:
            raise HTTPException(422, "invalid_phone")
        if body.role == "doctor" and not body.professional_id.strip():
            raise HTTPException(422, "professional_id_required")
        ph = phone_hmac(phone, settings_of(request))
        who = Link.invitee_phone_hmac == ph
    dup = db.execute(select(Link).where(
        Link.patient_id == p.id, Link.member_role == body.role, who,
        Link.status.in_(("pending", "accepted")),
    )).scalar_one_or_none()
    if dup:
        raise HTTPException(409, "already_invited")
    link = Link(patient_id=p.id, member_role=body.role, invitee_phone_hmac=ph,
                invitee_care_id=care_id,
                invitee_name=body.name.strip(), professional_id=body.professional_id.strip())
    db.add(link)
    db.flush()
    audit.record(db, user.id, "invite_created",
                 f"patient={p.id} link={link.id} role={body.role}")
    return _link_out(link, db)


@router.get("/{patient_id}/links", response_model=list[LinkOut])
def list_links(patient_id: str, user: User = Depends(current_user),
               db: Session = Depends(get_db)):
    p = patient_for_owner(db, user, patient_id)
    rows = db.execute(select(Link).where(Link.patient_id == p.id)
                      .order_by(Link.created_at)).scalars().all()
    return [_link_out(l, db) for l in rows]


# ---- sync ----------------------------------------------------------------------

@router.post("/{patient_id}/sync", response_model=SyncOut)
def sync(patient_id: str, body: SyncIn, user: User = Depends(current_user),
         db: Session = Depends(get_db)):
    """Idempotent upload of what the app holds offline. Needs the 'sync'
    purpose; game results also need 'gameplay', reminders need 'reminders'.
    Sessions are immutable once stored; schedules can change; marks are unique
    per reminder per day."""
    p = patient_for_owner(db, user, patient_id)
    if not consent_granted(db, p.id, "sync"):
        raise HTTPException(403, "consent_required")
    n_sessions = n_schedules = n_marks = 0

    if consent_granted(db, p.id, "gameplay"):
        for s in body.sessions:
            if db.get(GameSession, s.id) is not None:
                continue
            db.add(GameSession(
                id=s.id, patient_id=p.id, game=s.game,
                started_at=naive_utc(s.started_at), ended_at=naive_utc(s.ended_at),
                start_level=s.start_level, end_level=s.end_level, trials=s.trials,
                correct=min(s.correct, s.trials), level_stats=s.level_stats))
            n_sessions += 1

    if consent_granted(db, p.id, "reminders"):
        for r in body.schedules:
            row = db.get(ReminderSchedule, r.id)
            if row is not None and row.patient_id != p.id:
                continue
            if row is None:
                row = ReminderSchedule(id=r.id, patient_id=p.id)
                db.add(row)
            row.kind, row.hour, row.minute = r.kind, r.hour, r.minute
            row.days_mask, row.on_date, row.active = r.days_mask, r.on_date, r.active
            row.created_at = naive_utc(r.created_at)
            n_schedules += 1
        db.flush()
        known = {(m.reminder_id, m.day) for m in db.execute(
            select(ReminderMark).where(ReminderMark.patient_id == p.id)).scalars()}
        for m in body.marks:
            if (m.reminder_id, m.day) in known:
                continue
            db.add(ReminderMark(patient_id=p.id, reminder_id=m.reminder_id,
                                day=m.day, marked_at=naive_utc(m.marked_at)))
            known.add((m.reminder_id, m.day))
            n_marks += 1

    audit.record(db, user.id, "sync",
                 f"patient={p.id} sessions={n_sessions} schedules={n_schedules} marks={n_marks}")
    return SyncOut(sessions=n_sessions, schedules=n_schedules, marks=n_marks)


# ---- access and erasure (DPDP) ---------------------------------------------------

@router.get("/{patient_id}/export")
def export(patient_id: str, user: User = Depends(current_user),
           db: Session = Depends(get_db)):
    """Right of access: everything the server holds about the patient."""
    p = patient_for_owner(db, user, patient_id)

    def rows(model, *where):
        return [{c.name: (v.isoformat() if isinstance(v := getattr(r, c.name), datetime) else v)
                 for c in model.__table__.columns}
                for r in db.execute(select(model).where(*where)).scalars()]

    links = rows(Link, Link.patient_id == p.id)
    for l in links:
        l.pop("invitee_phone_hmac", None)
    audit.record(db, user.id, "patient_exported", f"patient={p.id}")
    return {
        "account": {"id": user.id, "role": user.role, "name": user.name,
                    "phone_last4": user.phone_last4},
        "patient": rows(Patient, Patient.id == p.id),
        "consents": rows(Consent, Consent.patient_id == p.id),
        "links": links,
        "sessions": rows(GameSession, GameSession.patient_id == p.id),
        "reminder_schedules": rows(ReminderSchedule, ReminderSchedule.patient_id == p.id),
        "reminder_marks": rows(ReminderMark, ReminderMark.patient_id == p.id),
    }


SNAPSHOT_MAX_SESSIONS = 2000
SNAPSHOT_MARK_DAYS = 400


@router.get("/{patient_id}/snapshot")
def snapshot(patient_id: str, user: User = Depends(current_user),
             db: Session = Depends(get_db)):
    """What a new phone needs to carry on: profile, the full consent history (so
    the current state and its record are both restored), game history, reminder
    timing and done marks. Only the patient may read it. Photos, family contacts,
    reminder text and the caregiver PIN were never sent, so they are not here."""
    p = patient_for_owner(db, user, patient_id)
    consents = db.execute(select(Consent).where(Consent.patient_id == p.id)
                          .order_by(Consent.id)).scalars().all()
    sessions = db.execute(select(GameSession).where(GameSession.patient_id == p.id)
                          .order_by(GameSession.ended_at.desc())
                          .limit(SNAPSHOT_MAX_SESSIONS)).scalars().all()
    since = (utcnow() - timedelta(days=SNAPSHOT_MARK_DAYS)).date().isoformat()
    marks = db.execute(select(ReminderMark).where(
        ReminderMark.patient_id == p.id, ReminderMark.day >= since)).scalars().all()
    schedules = db.execute(select(ReminderSchedule).where(
        ReminderSchedule.patient_id == p.id)).scalars().all()
    links = db.execute(select(Link).where(Link.patient_id == p.id)).scalars().all()
    audit.record(db, user.id, "patient_snapshot_read", f"patient={p.id}")

    def iso(d: datetime) -> str:
        return d.isoformat()

    return {
        "patient": _out(p).model_dump(),
        "consents": [{"purpose": c.purpose, "granted": c.granted,
                      "given_by_name": c.given_by_name,
                      "given_by_relation": c.given_by_relation,
                      "notice_version": c.notice_version, "created_at": iso(c.created_at)}
                     for c in consents],
        "sessions": [{"id": x.id, "game": x.game, "started_at": iso(x.started_at),
                      "ended_at": iso(x.ended_at), "start_level": x.start_level,
                      "end_level": x.end_level, "trials": x.trials,
                      "correct": x.correct, "level_stats": x.level_stats}
                     for x in reversed(sessions)],
        "schedules": [{"id": r.id, "kind": r.kind, "hour": r.hour, "minute": r.minute,
                       "days_mask": r.days_mask, "on_date": r.on_date,
                       "active": r.active, "created_at": iso(r.created_at)}
                      for r in schedules],
        "marks": [{"reminder_id": m.reminder_id, "day": m.day,
                   "marked_at": iso(m.marked_at)} for m in marks],
        "links": [{"id": l.id, "kind": l.member_role, "name": l.invitee_name,
                   "professional_id": l.professional_id, "status": l.status}
                  for l in links],
    }


@router.delete("/{patient_id}", status_code=204)
def erase(patient_id: str, user: User = Depends(current_user),
          db: Session = Depends(get_db)):
    """Right of erasure: removes the patient, everything linked, and the login.
    The audit log keeps only the fact that erasure happened."""
    p = patient_for_owner(db, user, patient_id)
    for model in (ReminderMark, ReminderSchedule, GameSession, Consent, Link):
        db.execute(delete(model).where(model.patient_id == p.id))
    db.execute(delete(Patient).where(Patient.id == p.id))
    db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    db.execute(delete(OtpChallenge).where(OtpChallenge.phone_hmac == user.phone_hmac,
                                          OtpChallenge.role == user.role))
    db.execute(delete(User).where(User.id == user.id))
    audit.record(db, user.id, "patient_erased", f"patient={p.id}")
