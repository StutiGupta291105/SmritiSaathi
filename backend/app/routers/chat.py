"""Messages between a patient and the caretaker or doctor linked to them.

A conversation is the link. Both sides see it only while the link is accepted
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
from ..models import ROLE_PURPOSE, DeviceToken, Link, Message, Patient, User
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


def _link_for(db: Session, user: User, link_id: str) -> tuple[Link, Patient]:
    """The conversation, if this user is in it and sharing is still allowed.
    Anything else looks like 'not found'."""
    link = db.get(Link, link_id)
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
    return link, p


def _out(m: Message, me: User) -> MessageOut:
    return MessageOut(id=m.id, sender_id=m.sender_id, mine=m.sender_id == me.id,
                      kind=m.kind, text=m.body, mime=m.mime, duration_ms=m.duration_ms,
                      has_media=m.media is not None, created_at=m.created_at,
                      read=m.read_at is not None)


def _unread(db: Session, link_id: str, me: User) -> int:
    return db.scalar(select(func.count()).select_from(Message).where(
        Message.link_id == link_id, Message.sender_id != me.id,
        Message.read_at.is_(None))) or 0


@router.get("/threads")
def threads(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Every conversation this person can open, with unread counts."""
    if user.role == "patient":
        rows = db.execute(select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
                          .where(Patient.user_id == user.id, Link.status == "accepted",
                                 Link.member_user_id.is_not(None))).all()
    else:
        rows = db.execute(select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
                          .where(Link.member_user_id == user.id, Link.status == "accepted",
                                 Link.member_role == user.role)).all()
    out = []
    for link, p in rows:
        if not consent_granted(db, p.id, ROLE_PURPOSE[link.member_role]):
            continue
        member = db.get(User, link.member_user_id)
        last = db.execute(select(Message).where(Message.link_id == link.id)
                          .order_by(Message.id.desc()).limit(1)).scalar_one_or_none()
        out.append({
            "link_id": link.id, "patient_id": p.id, "patient_name": p.display_name,
            "member_role": link.member_role,
            "member_name": member.name if member else link.invitee_name,
            # only the person who chose to share a number is callable, and only
            # by the patient they are linked to
            "member_phone": (member.contact_phone if member and user.role == "patient"
                             else None),
            "unread": _unread(db, link.id, user),
            "last_at": last.created_at.isoformat() if last else None,
            "last_kind": last.kind if last else None,
        })
    return out


@router.get("/{link_id}/messages", response_model=list[MessageOut])
def messages(link_id: str, after: int = 0, before: int = 0,
             user: User = Depends(current_user), db: Session = Depends(get_db)):
    """New messages (after=<id>), or an older page (before=<id>), oldest first.
    With neither: the latest page."""
    _link_for(db, user, link_id)
    q = select(Message).where(Message.link_id == link_id)
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
    link, p = _link_for(db, user, link_id)
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
    m = Message(link_id=link.id, sender_id=user.id, kind=body.kind, body=text,
                media=media, mime=mime, duration_ms=body.duration_ms if body.kind == "voice" else 0)
    db.add(m)
    db.flush()
    audit.record(db, user.id, "message_sent", f"link={link.id} kind={body.kind}")
    recipient_id = link.member_user_id if user.role == "patient" else p.user_id
    _push(request, db, recipient_id)
    return _out(m, user)


def _looks_like_image(b: bytes) -> bool:
    return (b[:3] == b"\xff\xd8\xff" or b[:8] == b"\x89PNG\r\n\x1a\n"
            or (b[:4] == b"RIFF" and b[8:12] == b"WEBP"))


def _push(request: Request, db: Session, user_id: str | None) -> None:
    """Best effort: a failed push never fails the message."""
    if not user_id:
        return
    provider = request.app.state.push
    tokens = db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id)).scalars().all()
    for t in tokens:
        try:
            result = provider.send(t.token, PUSH_TITLE, PUSH_BODY)
        except Exception:
            continue
        if result == INVALID:
            db.execute(delete(DeviceToken).where(DeviceToken.id == t.id))


@router.get("/media/{message_id}")
def media(message_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    m = db.get(Message, message_id)
    if m is None or m.media is None:
        raise HTTPException(404, "not_found")
    _link_for(db, user, m.link_id)
    return Response(content=m.media, media_type=m.mime or "application/octet-stream")


@router.post("/{link_id}/read", status_code=204)
def mark_read(link_id: str, body: ReadIn, user: User = Depends(current_user),
              db: Session = Depends(get_db)):
    """The reader has seen everything the other person sent up to this message."""
    _link_for(db, user, link_id)
    db.execute(update(Message).where(
        Message.link_id == link_id, Message.sender_id != user.id,
        Message.id <= body.upto, Message.read_at.is_(None)).values(read_at=utcnow()))
    return Response(status_code=204)
