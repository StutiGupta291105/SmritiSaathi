from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .. import audit
from ..db import utcnow
from ..deps import current_user, get_db
from ..models import DeviceToken, User

router = APIRouter(prefix="/v1/devices", tags=["devices"])


class DeviceIn(BaseModel):
    token: str = Field(min_length=20, max_length=512)
    platform: str = Field(default="android", pattern="^(android|ios)$")


@router.post("", status_code=204)
def register(body: DeviceIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Registers this phone for push. A token belongs to one account at a time:
    signing in as someone else on the same phone moves it."""
    row = db.execute(select(DeviceToken).where(DeviceToken.token == body.token)).scalar_one_or_none()
    if row is None:
        db.add(DeviceToken(user_id=user.id, token=body.token, platform=body.platform))
    else:
        row.user_id, row.platform, row.last_seen = user.id, body.platform, utcnow()
    audit.record(db, user.id, "device_registered", f"platform={body.platform}")
    return Response(status_code=204)


@router.delete("", status_code=204)
def unregister(body: DeviceIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.execute(delete(DeviceToken).where(DeviceToken.token == body.token,
                                         DeviceToken.user_id == user.id))
    return Response(status_code=204)
