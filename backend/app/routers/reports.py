"""Report an objectionable AI answer or chat message. Google Play requires apps with
AI-generated content and with user-to-user messages to let people flag it in the app.
Anyone signed in can report; a person can send at most 20 a day (a button that anyone
could press forever would otherwise be a way to fill the table)."""
from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import current_user, get_db
from ..models import Report, User

router = APIRouter(prefix="/v1/reports", tags=["reports"])
DAILY_LIMIT = 20


class ReportIn(BaseModel):
    kind: Literal["ai", "chat"]
    ref: str = Field(default="", max_length=64)
    excerpt: str = Field(default="", max_length=500)
    reason: str = Field(default="", max_length=120)


@router.post("", status_code=201)
def report(body: ReportIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    since = utcnow() - timedelta(days=1)
    today = db.execute(select(func.count()).select_from(Report).where(
        Report.reporter_id == user.id, Report.created_at >= since)).scalar_one()
    if today >= DAILY_LIMIT:
        raise HTTPException(429, "too_many_reports")
    db.add(Report(reporter_id=user.id, kind=body.kind, ref=body.ref.strip(),
                  excerpt=body.excerpt.strip(), reason=body.reason.strip()))
    audit.record(db, user.id, "content_reported", f"kind={body.kind} ref={body.ref.strip()[:36]}")
    db.commit()
    return {"ok": True}
