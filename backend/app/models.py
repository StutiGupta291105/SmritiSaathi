"""Server data model. Deliberately small (data minimisation): no phone numbers
in the clear, no photos, no family contacts, no free-text reminder labels."""
import uuid
from datetime import datetime

from sqlalchemy import (Boolean, DateTime, LargeBinary, ForeignKey, Index, Integer, String,
                        Text, UniqueConstraint)
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, utcnow

ROLES = ("patient", "doctor", "caretaker")
LINK_ROLES = ("doctor", "caretaker")
CONSENT_PURPOSES = (
    "gameplay", "reminders", "family_contacts", "doctor_share",
    "caregiver_share", "location", "sync", "companion",
)
# Which consent purpose gates each kind of linked member.
ROLE_PURPOSE = {"caretaker": "caregiver_share", "doctor": "doctor_share"}


def new_id() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    phone_hmac: Mapped[str] = mapped_column(String(64), index=True)
    phone_last4: Mapped[str] = mapped_column(String(4))
    role: Mapped[str] = mapped_column(String(12))
    name: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    # Set by an operator after checking a doctor's registration; never by the user.
    verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # What a patient types to invite this caretaker or doctor (CG-XXXXXX / DR-XXXXXX).
    care_id: Mapped[str | None] = mapped_column(String(12), nullable=True, index=True)
    # A caretaker's or doctor's own choice: the number patients linked to them may call.
    contact_phone: Mapped[str | None] = mapped_column(String(24), nullable=True)
    __table_args__ = (UniqueConstraint("phone_hmac", "role", name="uq_user_phone_role"),)


class OtpChallenge(Base):
    __tablename__ = "otp_challenges"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    phone_hmac: Mapped[str] = mapped_column(String(64), index=True)
    phone_last4: Mapped[str] = mapped_column(String(4), default="")
    role: Mapped[str] = mapped_column(String(12))
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    consumed: Mapped[bool] = mapped_column(Boolean, default=False)
    ip_hmac: Mapped[str] = mapped_column(String(64), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Patient(Base):
    __tablename__ = "patients"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True)
    display_name: Mapped[str] = mapped_column(String(120))
    language: Mapped[str] = mapped_column(String(8), default="en")
    baseline_level: Mapped[int] = mapped_column(Integer, default=2)
    # Minutes ahead of UTC (India = 330). Needed to group games and reminders
    # into the patient's own calendar days.
    tz_offset_minutes: Mapped[int] = mapped_column(Integer, default=330)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Link(Base):
    """A patient's invite to a caretaker or doctor, and its outcome."""
    __tablename__ = "links"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    member_role: Mapped[str] = mapped_column(String(12))
    invitee_phone_hmac: Mapped[str] = mapped_column(String(64), index=True, default="")
    invitee_care_id: Mapped[str | None] = mapped_column(String(12), nullable=True, index=True)
    invitee_name: Mapped[str] = mapped_column(String(120))
    professional_id: Mapped[str] = mapped_column(String(64), default="")
    member_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    status: Mapped[str] = mapped_column(String(12), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Consent(Base):
    """Append-only consent log; the newest row per purpose is the current state."""
    __tablename__ = "consents"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    purpose: Mapped[str] = mapped_column(String(24))
    granted: Mapped[bool] = mapped_column(Boolean)
    given_by_name: Mapped[str] = mapped_column(String(120))
    given_by_relation: Mapped[str] = mapped_column(String(40))
    notice_version: Mapped[str] = mapped_column(String(16))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class GameSession(Base):
    __tablename__ = "game_sessions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # client uuid
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    game: Mapped[str] = mapped_column(String(24))
    started_at: Mapped[datetime] = mapped_column(DateTime)
    ended_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    start_level: Mapped[int] = mapped_column(Integer)
    end_level: Mapped[int] = mapped_column(Integer)
    trials: Mapped[int] = mapped_column(Integer)
    correct: Mapped[int] = mapped_column(Integer)
    level_stats: Mapped[str | None] = mapped_column(Text, nullable=True)
    received_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ReminderSchedule(Base):
    """A reminder's timing only, no label (so no medicine names), so adherence
    can be computed for caregivers and doctors."""
    __tablename__ = "reminder_schedules"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # client uuid
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    kind: Mapped[str] = mapped_column(String(16))
    hour: Mapped[int] = mapped_column(Integer)
    minute: Mapped[int] = mapped_column(Integer)
    days_mask: Mapped[int] = mapped_column(Integer, default=127)
    on_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class ReminderMark(Base):
    __tablename__ = "reminder_marks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    reminder_id: Mapped[str] = mapped_column(String(36))
    day: Mapped[str] = mapped_column(String(10))
    marked_at: Mapped[datetime] = mapped_column(DateTime)
    __table_args__ = (
        UniqueConstraint("patient_id", "reminder_id", "day", name="uq_mark"),
        Index("ix_mark_patient_day", "patient_id", "day"),
    )


class AuditEntry(Base):
    """Append-only, hash-chained (each entry commits to the one before)."""
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ts: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(40))
    action: Mapped[str] = mapped_column(String(48))
    detail: Mapped[str] = mapped_column(Text)
    prev_hash: Mapped[str] = mapped_column(String(64))
    hash: Mapped[str] = mapped_column(String(64))


class AuditHead(Base):
    """Newest audit entry, signed with a key that is not in the database. Without
    it, deleting the last entries of a hash chain cannot be noticed."""
    __tablename__ = "audit_head"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)  # always 1
    last_id: Mapped[int] = mapped_column(Integer)
    last_hash: Mapped[str] = mapped_column(String(64))
    mac: Mapped[str] = mapped_column(String(64))


class ChatUsage(Base):
    """Messages answered per patient per day, only to limit use. No content."""
    __tablename__ = "chat_usage"
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)


class DeviceToken(Base):
    """A phone registered for push notifications."""
    __tablename__ = "device_tokens"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    token: Mapped[str] = mapped_column(String(512), unique=True)
    platform: Mapped[str] = mapped_column(String(8), default="android")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_seen: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class PushSent(Base):
    """One push per alert kind per person per day, so nobody is nagged."""
    __tablename__ = "push_sent"
    user_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    patient_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    kind: Mapped[str] = mapped_column(String(32), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)


class Message(Base):
    """One chat message between a patient and a linked caretaker or doctor. A
    conversation is the link. Text, a photo or a voice note; the media bytes are
    kept here, never in the audit log, and go when the patient is erased."""
    __tablename__ = "messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    link_id: Mapped[str] = mapped_column(ForeignKey("links.id"), index=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(8))  # text | image | voice
    body: Mapped[str] = mapped_column(Text, default="")
    media: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    mime: Mapped[str] = mapped_column(String(32), default="")
    duration_ms: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class CareReminder(Base):
    """A routine or reminder a caretaker or doctor set for the patient. Unlike the
    patient's own reminders, its title is stored here, because the patient's phone
    has to receive it. The patient's phone copies it and may delete it."""
    __tablename__ = "care_reminders"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_by_name: Mapped[str] = mapped_column(String(120))
    created_by_role: Mapped[str] = mapped_column(String(12))
    kind: Mapped[str] = mapped_column(String(16))
    label: Mapped[str] = mapped_column(String(120), default="")
    hour: Mapped[int] = mapped_column(Integer)
    minute: Mapped[int] = mapped_column(Integer)
    days_mask: Mapped[int] = mapped_column(Integer, default=127)
    on_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
