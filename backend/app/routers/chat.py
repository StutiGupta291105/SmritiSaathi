"""Messages between a patient and the caretaker or doctor linked to them, between a patient
and any doctor they ask for an opinion, and between the caregiver and the doctor of one
patient.

A care conversation is the link. Both sides see it only while the link is accepted
and the patient's matching sharing consent is on, so withdrawing consent or
ending the link closes the chat at once (the history stays for the patient's
export and is deleted with the patient). Text, photos and voice notes are kept
in the database. A push only says "new message"; it never carries the content.
"""
import base64
import binascii
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import consent_granted, current_user, get_db
from ..models import ROLE_PURPOSE, Conversation, DeviceToken, Link, Message, Patient, User
from ..push import INVALID, OK

router = APIRouter(prefix="/v1/chat", tags=["chat"])

MAX_TEXT = 2000
MAX_MEDIA = 600_000  # bytes after decoding; the whole request stays under 1 MB
MAX_VOICE_MS = 120_000
IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
VOICE_TYPES = {"audio/mp4", "audio/aac", "audio/m4a", "audio/x-m4a", "audio/mpeg",
               "audio/ogg", "audio/webm", "audio/3gpp"}
PUSH_TITLE = "Smriti Sathi"
PUSH_BODY = "You have a new message."
ROUTINE_BODY = "Your daily routine was updated."
PAGE = 50


class MessageIn(BaseModel):
    kind: str = Field(pattern="^(text|image|voice)$")
    text: str = Field(default="", max_length=MAX_TEXT)
    media_b64: str = Field(default="", max_length=MAX_MEDIA * 4 // 3 + 16)
    mime: str = Field(default="", max_length=32)
    duration_ms: int = Field(default=0, ge=0, le=MAX_VOICE_MS)


class MessageOut(BaseModel):
    id: int
    sender_id: str
    mine: bool
    kind: str
    text: str
    mime: str
    duration_ms: int
    has_media: bool
    created_at: datetime
    read: bool


class ReadIn(BaseModel):
    upto: int = Field(ge=0)


class _Thread:
    """One conversation the caller may use: a care link, or a Conversation."""

    def __init__(self, tid: str, patient: Patient, members: tuple[str | None, str | None],
                 conv: Conversation | None = None, link: Link | None = None):
        self.id, self.patient, self.members, self.conv, self.link = tid, patient, members, conv, link

    @property
    def kind(self) -> str:
        return "care" if self.link else self.conv.kind  # type: ignore[union-attr]

    def other(self, user: User) -> str | None:
        a, b = self.members
        return b if user.id == a else a

    def where(self):
        return Message.conv_id == self.id if self.conv else Message.link_id == self.id


def _pro_open(db: Session, c: Conversation) -> bool:
    """A caregiver-doctor chat lasts only while both are still linked to the patient
    and the patient still shares with both."""
    for uid, role in ((c.caregiver_id, "caretaker"), (c.doctor_id, "doctor")):
        ok = db.execute(select(Link.id).where(
            Link.patient_id == c.patient_id, Link.member_user_id == uid,
            Link.member_role == role, Link.status == "accepted")).first()
        if not ok or not consent_granted(db, c.patient_id, ROLE_PURPOSE[role]):
            return False
    return True


def _thread_for(db: Session, user: User, tid: str) -> _Thread:
    """The conversation, if this user is in it and it is still allowed.
    Anything else looks like 'not found'."""
    conv = db.get(Conversation, tid)
    if conv is not None:
        p = db.get(Patient, conv.patient_id)
        if p is None:
            raise HTTPException(404, "not_found")
        if conv.kind == "opinion":
            ok = (user.role == "patient" and p.user_id == user.id) or (
                user.role == "doctor" and user.id == conv.doctor_id)
            if not ok:
                raise HTTPException(404, "not_found")
            return _Thread(tid, p, (p.user_id, conv.doctor_id), conv=conv)
        if user.id not in (conv.caregiver_id, conv.doctor_id) or not _pro_open(db, conv):
            raise HTTPException(404, "not_found")
        return _Thread(tid, p, (conv.caregiver_id, conv.doctor_id), conv=conv)
    link = db.get(Link, tid)
    if link is None or link.status != "accepted" or link.member_user_id is None:
        raise HTTPException(404, "not_found")
    p = db.get(Patient, link.patient_id)
    if p is None:
        raise HTTPException(404, "not_found")
    is_patient = user.role == "patient" and p.user_id == user.id
    is_member = user.id == link.member_user_id and user.role == link.member_role
    if not (is_patient or is_member):
        raise HTTPException(404, "not_found")
    if not consent_granted(db, p.id, ROLE_PURPOSE[link.member_role]):
        raise HTTPException(404, "not_found")
    return _Thread(tid, p, (p.user_id, link.member_user_id), link=link)


def _out(m: Message, me: User) -> MessageOut:
    return MessageOut(id=m.id, sender_id=m.sender_id, mine=m.sender_id == me.id,
                      kind=m.kind, text=m.body, mime=m.mime, duration_ms=m.duration_ms,
                      has_media=m.media is not None, created_at=m.created_at,
                      read=m.read_at is not None)


def _unread(db: Session, t: _Thread, me: User) -> int:
    return db.scalar(select(func.count()).select_from(Message).where(
        t.where(), Message.sender_id != me.id, Message.read_at.is_(None))) or 0


def _ensure_pro(db: Session, user: User) -> None:
    """The caregiver and the doctor linked to one patient are put in touch as soon
    as both invitations are accepted: this creates their shared conversation."""
    other = "doctor" if user.role == "caretaker" else "caretaker"
    mine = db.execute(select(Link).where(
        Link.member_user_id == user.id, Link.member_role == user.role,
        Link.status == "accepted")).scalars().all()
    for ln in mine:
        if not consent_granted(db, ln.patient_id, ROLE_PURPOSE[user.role]):
            continue
        if not consent_granted(db, ln.patient_id, ROLE_PURPOSE[other]):
            continue
        for ol in db.execute(select(Link).where(
                Link.patient_id == ln.patient_id, Link.member_role == other,
                Link.status == "accepted", Link.member_user_id.is_not(None))).scalars():
            cg, dr = (user.id, ol.member_user_id) if user.role == "caretaker" else (ol.member_user_id, user.id)
            exists = db.execute(select(Conversation.id).where(
                Conversation.kind == "pro", Conversation.patient_id == ln.patient_id,
                Conversation.caregiver_id == cg, Conversation.doctor_id == dr)).first()
            if not exists:
                db.add(Conversation(kind="pro", patient_id=ln.patient_id,
                                    caregiver_id=cg, doctor_id=dr))
    db.flush()


@router.get("/threads")
def threads(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Every conversation this person can open, with unread counts.

    `kind`: "care" (patient and their linked caregiver/doctor), "opinion" (a patient
    and a doctor they are not linked to) or "pro" (caregiver and doctor about a
    patient). `peer_name`/`peer_role` always describe the other person."""
    if user.role in ("caretaker", "doctor"):
        _ensure_pro(db, user)
    if user.role == "patient":
        rows = db.execute(select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
                          .where(Patient.user_id == user.id, Link.status == "accepted",
                                 Link.member_user_id.is_not(None))).all()
    else:
        rows = db.execute(select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
                          .where(Link.member_user_id == user.id, Link.status == "accepted",
                                 Link.member_role == user.role)).all()
    out = []

    def last_of(t: _Thread):
        return db.execute(select(Message).where(t.where())
                          .order_by(Message.id.desc()).limit(1)).scalar_one_or_none()

    for link, p in rows:
        if not consent_granted(db, p.id, ROLE_PURPOSE[link.member_role]):
            continue
        member = db.get(User, link.member_user_id)
        t = _Thread(link.id, p, (p.user_id, link.member_user_id), link=link)
        last = last_of(t)
        peer_name = (member.name if member else link.invitee_name) if user.role == "patient" else p.display_name
        out.append({
            "link_id": link.id, "kind": "care", "patient_id": p.id, "patient_name": p.display_name,
            "member_role": link.member_role,
            "member_name": member.name if member else link.invitee_name,
            "peer_name": peer_name,
            "peer_role": link.member_role if user.role == "patient" else "patient",
            # only the person who chose to share a number is callable, and only
            # by the patient they are linked to
            "member_phone": (member.contact_phone if member and user.role == "patient"
                             else None),
            "unread": _unread(db, t, user),
            "last_at": last.created_at.isoformat() if last else None,
            "last_kind": last.kind if last else None,
        })
    if user.role == "patient":
        convs = db.execute(select(Conversation, Patient).join(Patient, Patient.id == Conversation.patient_id)
                           .where(Patient.user_id == user.id, Conversation.kind == "opinion")).all()
    elif user.role == "doctor":
        convs = db.execute(select(Conversation, Patient).join(Patient, Patient.id == Conversation.patient_id)
                           .where(Conversation.doctor_id == user.id)).all()
    else:
        convs = db.execute(select(Conversation, Patient).join(Patient, Patient.id == Conversation.patient_id)
                           .where(Conversation.caregiver_id == user.id)).all()
    for c, p in convs:
        if c.kind == "pro" and not _pro_open(db, c):
            continue
        if user.role == "caretaker" and c.kind != "pro":
            continue
        doc = db.get(User, c.doctor_id)
        cg = db.get(User, c.caregiver_id) if c.caregiver_id else None
        t = _Thread(c.id, p, (p.user_id if c.kind == "opinion" else c.caregiver_id, c.doctor_id), conv=c)
        last = last_of(t)
        if c.kind == "opinion":
            peer_name = (doc.name if doc else "") if user.role == "patient" else p.display_name
            peer_role = "doctor" if user.role == "patient" else "patient"
        else:
            peer = doc if user.role == "caretaker" else cg
            peer_name = peer.name if peer else ""
            peer_role = "doctor" if user.role == "caretaker" else "caretaker"
        out.append({
            # A care-team chat is about a patient both people are linked to, so its id
            # is shown; an opinion chat never reveals one (the doctor has no access).
            "link_id": c.id, "kind": c.kind,
            "patient_id": p.id if c.kind == "pro" else None, "patient_name": p.display_name,
            "member_role": "doctor" if user.role == "patient" else peer_role,
            "member_name": peer_name, "peer_name": peer_name, "peer_role": peer_role,
            "member_phone": None,
            "unread": _unread(db, t, user),
            "last_at": last.created_at.isoformat() if last else None,
            "last_kind": last.kind if last else None,
        })
    return out


class OpinionIn(BaseModel):
    doctor_id: str = Field(min_length=1, max_length=36)


@router.get("/doctors")
def doctor_directory(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """For a patient's "Talk to Doctor": the doctor(s) they are linked to come first
    (pinned), then every other doctor on the app. Only names and a verified flag are
    shown, never a phone number."""
    if user.role != "patient":
        raise HTTPException(403, "patients_only")
    p = db.execute(select(Patient).where(Patient.user_id == user.id)).scalar_one_or_none()
    if p is None:
        raise HTTPException(404, "not_found")
    pinned: dict[str, str | None] = {}
    for ln in db.execute(select(Link).where(
            Link.patient_id == p.id, Link.member_role == "doctor", Link.status == "accepted",
            Link.member_user_id.is_not(None))).scalars():
        pinned[ln.member_user_id] = ln.id if consent_granted(db, p.id, "doctor_share") else None
    opinions = {c.doctor_id: c.id for c in db.execute(select(Conversation).where(
        Conversation.patient_id == p.id, Conversation.kind == "opinion")).scalars()}
    out = []
    for d in db.execute(select(User).where(User.role == "doctor")).scalars():
        is_pinned = d.id in pinned
        out.append({"doctor_id": d.id, "name": d.name, "verified": d.verified_at is not None,
                    "pinned": is_pinned, "thread_id": pinned[d.id] if is_pinned else opinions.get(d.id)})
    out.sort(key=lambda x: (not x["pinned"], not x["verified"], x["name"].lower()))
    return out


@router.post("/opinion")
def open_opinion(body: OpinionIn, user: User = Depends(current_user),
                 db: Session = Depends(get_db)):
    """A patient starts (or reopens) a conversation with any doctor. If that doctor is
    already the patient's own, the care chat is returned instead."""
    if user.role != "patient":
        raise HTTPException(403, "patients_only")
    p = db.execute(select(Patient).where(Patient.user_id == user.id)).scalar_one_or_none()
    doc = db.get(User, body.doctor_id)
    if p is None or doc is None or doc.role != "doctor":
        raise HTTPException(404, "not_found")
    own = db.execute(select(Link).where(
        Link.patient_id == p.id, Link.member_user_id == doc.id, Link.member_role == "doctor",
        Link.status == "accepted")).scalar_one_or_none()
    if own is not None and consent_granted(db, p.id, "doctor_share"):
        return {"thread_id": own.id, "kind": "care"}
    c = db.execute(select(Conversation).where(
        Conversation.kind == "opinion", Conversation.patient_id == p.id,
        Conversation.doctor_id == doc.id)).scalar_one_or_none()
    if c is None:
        c = Conversation(kind="opinion", patient_id=p.id, doctor_id=doc.id)
        db.add(c)
        db.flush()
        audit.record(db, user.id, "opinion_chat_opened", f"conversation={c.id}")
    return {"thread_id": c.id, "kind": "opinion"}


@router.get("/{link_id}/messages", response_model=list[MessageOut])
def messages(link_id: str, after: int = 0, before: int = 0,
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    """New messages (after=<id>), or an older page (before=<id>), oldest first.
    With neither: the latest page."""
    t = _thread_for(db, user, link_id)
    q = select(Message).where(t.where())
    if after:
        rows = db.execute(q.where(Message.id > after).order_by(Message.id).limit(200)).scalars().all()
    elif before:
        rows = list(reversed(db.execute(q.where(Message.id < before)
                                        .order_by(Message.id.desc()).limit(PAGE)).scalars().all()))
    else:
        rows = list(reversed(db.execute(q.order_by(Message.id.desc()).limit(PAGE)).scalars().all()))
    return [_out(m, user) for m in rows]


@router.post("/{link_id}/messages", response_model=MessageOut, status_code=201)
def send(link_id: str, body: MessageIn, request: Request,
         user: User = Depends(current_user), db: Session = Depends(get_db)):
    t = _thread_for(db, user, link_id)
    text, media, mime = body.text.strip(), None, ""
    if body.kind == "text":
        if not text:
            raise HTTPException(422, "empty_message")
    else:
        try:
            media = base64.b64decode(body.media_b64, validate=True)
        except (binascii.Error, ValueError):
            raise HTTPException(422, "invalid_media")
        if not media:
            raise HTTPException(422, "invalid_media")
        if len(media) > MAX_MEDIA:
            raise HTTPException(413, "media_too_large")
        mime = body.mime.lower()
        allowed = IMAGE_TYPES if body.kind == "image" else VOICE_TYPES
        if mime not in allowed:
            raise HTTPException(422, "unsupported_media")
        if body.kind == "image" and not _looks_like_image(media):
            raise HTTPException(422, "invalid_media")
        text = text[:500]
    m = Message(link_id=None if t.conv else t.id, conv_id=t.id if t.conv else None,
                sender_id=user.id, kind=body.kind, body=text,
                media=media, mime=mime, duration_ms=body.duration_ms if body.kind == "voice" else 0)
    db.add(m)
    db.flush()
    audit.record(db, user.id, "message_sent", f"thread={t.id} kind={body.kind}")
    notify_user(request, db, t.other(user))
    return _out(m, user)


def _looks_like_image(b: bytes) -> bool:
    return (b[:3] == b"\xff\xd8\xff" or b[:8] == b"\x89PNG\r\n\x1a\n"
            or (b[:4] == b"RIFF" and b[8:12] == b"WEBP"))


def notify_user(request: Request, db: Session, user_id: str | None, body: str = PUSH_BODY) -> None:
    """Best effort: a failed push never fails the action that caused it. The text is
    generic on purpose: lock screens are visible to other people."""
    if not user_id:
        return
    provider = request.app.state.push
    tokens = db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id)).scalars().all()
    for t in tokens:
        try:
            result = provider.send(t.token, PUSH_TITLE, body)
        except Exception:
            continue
        if result == INVALID:
            db.execute(delete(DeviceToken).where(DeviceToken.id == t.id))


@router.get("/media/{message_id}")
def media(message_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    m = db.get(Message, message_id)
    if m is None or m.media is None:
        raise HTTPException(404, "not_found")
    _thread_for(db, user, m.conv_id or m.link_id)
    return Response(content=m.media, media_type=m.mime or "application/octet-stream")


@router.post("/{link_id}/read", status_code=204)
def mark_read(link_id: str, body: ReadIn, user: User = Depends(current_user),
              db: Session = Depends(get_db)):
    """The reader has seen everything the other person sent up to this message."""
    t = _thread_for(db, user, link_id)
    db.execute(update(Message).where(
        t.where(), Message.sender_id != user.id,
        Message.id <= body.upto, Message.read_at.is_(None)).values(read_at=utcnow()))
    return Response(status_code=204)
