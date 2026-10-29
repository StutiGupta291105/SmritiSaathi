from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

Role = Literal["patient", "doctor", "caretaker"]
LinkRole = Literal["doctor", "caretaker"]
Purpose = Literal[
    "gameplay", "reminders", "family_contacts", "doctor_share",
    "caregiver_share", "location", "sync", "companion",
]


class OtpRequest(BaseModel):
    phone: str = Field(max_length=24)
    role: Role


class OtpRequestOut(BaseModel):
    challenge_id: str
    expires_in: int


class OtpVerify(BaseModel):
    challenge_id: str = Field(max_length=36)
    code: str = Field(pattern=r"^\d{6}$")
    mode: Literal["login", "signup"]
    name: str | None = Field(default=None, max_length=120)


class UserOut(BaseModel):
    id: str
    role: Role
    name: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class PatientIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)
    language: Literal["en", "hi", "bn", "as"] = "en"
    baseline_level: int = Field(default=2, ge=1, le=5)
    tz_offset_minutes: int = Field(default=330, ge=-720, le=840)


class PatientOut(BaseModel):
    id: str
    display_name: str
    language: str
    baseline_level: int
    tz_offset_minutes: int


class BaselineIn(BaseModel):
    baseline_level: int = Field(ge=1, le=5)


class ConsentIn(BaseModel):
    purpose: Purpose
    granted: bool
    given_by_name: str = Field(min_length=1, max_length=120)
    given_by_relation: str = Field(min_length=1, max_length=40)
    notice_version: str = Field(min_length=1, max_length=16)


class ConsentsIn(BaseModel):
    consents: list[ConsentIn] = Field(max_length=20)


class InviteIn(BaseModel):
    role: LinkRole
    phone: str = Field(max_length=24)
    name: str = Field(min_length=1, max_length=120)
    professional_id: str = Field(default="", max_length=64)


class LinkOut(BaseModel):
    id: str
    patient_id: str
    member_role: LinkRole
    invitee_name: str
    professional_id: str
    status: str
    created_at: datetime
    verified: bool = False  # the invitee's registration was checked by an operator


class InviteForMe(BaseModel):
    id: str
    patient_display_name: str
    member_role: LinkRole
    created_at: datetime


class SessionIn(BaseModel):
    id: str = Field(max_length=36)
    game: Literal["memory_match", "word_recall", "puzzle_fix", "number_order",
                  "attention", "routine"]
    started_at: datetime
    ended_at: datetime
    start_level: int = Field(ge=1, le=5)
    end_level: int = Field(ge=1, le=5)
    trials: int = Field(ge=0, le=1000)
    correct: int = Field(ge=0, le=1000)
    level_stats: str | None = Field(default=None, max_length=500)


class ScheduleIn(BaseModel):
    id: str = Field(max_length=36)
    kind: Literal["medicine", "hydration", "activity", "appointment"]
    hour: int = Field(ge=0, le=23)
    minute: int = Field(ge=0, le=59)
    days_mask: int = Field(default=127, ge=0, le=127)
    on_date: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    active: bool = True
    created_at: datetime


class MarkIn(BaseModel):
    reminder_id: str = Field(max_length=36)
    day: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    marked_at: datetime


class SyncIn(BaseModel):
    sessions: list[SessionIn] = Field(default_factory=list, max_length=500)
    schedules: list[ScheduleIn] = Field(default_factory=list, max_length=200)
    marks: list[MarkIn] = Field(default_factory=list, max_length=1000)


class SyncOut(BaseModel):
    sessions: int
    schedules: int
    marks: int
