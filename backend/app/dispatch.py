"""Sends one push per new attention alert to each caretaker or doctor who may
see the patient, at most once per alert kind per day. Run it from a scheduler:

    python -m app.cli send-alerts          # every 15 to 30 minutes
"""
from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .db import utcnow
from .deps import consent_granted
from .models import ROLE_PURPOSE, DeviceToken, Link, Patient, PushSent
from .push import INVALID, OK, PushProvider
from .routers.care import build_report

TITLE = "Smriti Sathi"
BODY = "There is an update about {name}. Open the app to see it."


def send_pending_alerts(db: Session, provider: PushProvider) -> int:
    sent = 0
    day = utcnow().date().isoformat()
    rows = db.execute(
        select(Link, Patient).join(Patient, Patient.id == Link.patient_id)
        .where(Link.status == "accepted", Link.member_user_id.is_not(None))).all()
    for link, p in rows:
        if not consent_granted(db, p.id, ROLE_PURPOSE[link.member_role]):
            continue
        tokens = db.execute(select(DeviceToken).where(
            DeviceToken.user_id == link.member_user_id)).scalars().all()
        if not tokens:
            continue
        alerts = [a for a in build_report(db, p, 7)["alerts"] if a["severity"] == "attention"]
        for a in alerts:
            key = (link.member_user_id, p.id, a["kind"], day)
            if db.get(PushSent, key) is not None:
                continue
            delivered = False
            for t in list(tokens):
                result = provider.send(t.token, TITLE, BODY.format(name=p.display_name))
                if result == OK:
                    delivered = True
                elif result == INVALID:
                    db.execute(delete(DeviceToken).where(DeviceToken.id == t.id))
                    tokens.remove(t)
            if delivered:
                db.add(PushSent(user_id=key[0], patient_id=key[1], kind=key[2], day=day))
                sent += 1
        db.flush()
    # Old send records are only for de-duplication; keep a short window.
    cutoff = (utcnow() - timedelta(days=14)).date().isoformat()
    db.execute(delete(PushSent).where(PushSent.day < cutoff))
    return sent
