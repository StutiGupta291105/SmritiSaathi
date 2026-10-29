from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, companion
from ..deps import consent_granted, current_user, get_db, patient_for_owner
from ..models import ChatUsage, User

router = APIRouter(prefix="/v1/patients", tags=["companion"])


class ChatMsg(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(max_length=2000)


class TodayItem(BaseModel):
    kind: str = Field(max_length=16)
    time: str = Field(max_length=5)  # HH:MM, local; reminder text is never sent
    done: bool = False


class ChatIn(BaseModel):
    messages: list[ChatMsg] = Field(max_length=40)
    lang: str = Field(default="en", max_length=4)
    first_name: str = Field(default="", max_length=60)
    now_text: str = Field(default="", max_length=80)
    today: list[TodayItem] = Field(default_factory=list, max_length=20)


class ChatOut(BaseModel):
    reply: str
    emergency: bool = False


@router.post("/{patient_id}/companion/chat", response_model=ChatOut)
def chat(patient_id: str, body: ChatIn, request: Request,
         user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Needs the patient's own login and the 'companion' consent. Nothing said
    is stored; only a daily count and an audit line without content."""
    p = patient_for_owner(db, user, patient_id)
    if not consent_granted(db, p.id, "companion"):
        raise HTTPException(403, "consent_required")
    lang = body.lang if body.lang in companion.LANGUAGE_NAMES else "en"
    turns = companion.clean_turns([m.model_dump() for m in body.messages])
    if not turns:
        raise HTTPException(422, "no_message")

    # Fixed safety reply, before any model and not counted against the limit.
    if companion.is_emergency(turns[-1].content, lang):
        audit.record(db, user.id, "companion_emergency_reply", f"patient={p.id}")
        return ChatOut(reply=companion.EMERGENCY_REPLY.get(lang, companion.EMERGENCY_REPLY["en"]), emergency=True)

    s = request.app.state.settings
    today = date.today().isoformat()
    usage = db.get(ChatUsage, (p.id, today))
    if usage is not None and usage.count >= s.companion_daily_limit:
        raise HTTPException(429, "daily_limit")

    system = companion.build_system(lang, body.first_name, body.now_text,
                                    [t.model_dump() for t in body.today])
    try:
        reply = request.app.state.companion.reply(
            system, [{"role": t.role, "content": t.content} for t in turns])
    except companion.CompanionUnavailable:
        raise HTTPException(503, "companion_unavailable")

    if usage is None:
        db.add(ChatUsage(patient_id=p.id, day=today, count=1))
    else:
        usage.count += 1
    audit.record(db, user.id, "companion_chat", f"patient={p.id} turns={len(turns)}")
    return ChatOut(reply=reply or companion.UNAVAILABLE_REPLY.get(lang, companion.UNAVAILABLE_REPLY["en"]))
