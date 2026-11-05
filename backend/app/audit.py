import hashlib
import hmac
import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import utcnow
from .models import AuditEntry, AuditHead

GENESIS = "GENESIS"


def _entry_hash(prev: str, ts: str, actor: str, action: str, detail: str) -> str:
    return hashlib.sha256(json.dumps([prev, ts, actor, action, detail]).encode()).hexdigest()


def _mac(key: str, last_id: int, last_hash: str) -> str:
    return hmac.new(key.encode(), f"{last_id}:{last_hash}".encode(), hashlib.sha256).hexdigest()


def _key(db: Session) -> str:
    return db.info["audit_key"]


def record(db: Session, actor: str, action: str, detail: str = "") -> None:
    """Appends to the audit log. Details are ids only: never phone numbers,
    names, or health content. Call inside the request's transaction."""
    last = db.execute(
        select(AuditEntry.hash).order_by(AuditEntry.id.desc()).limit(1)
    ).scalar_one_or_none()
    prev = last or GENESIS
    ts = utcnow()
    entry = AuditEntry(ts=ts, actor=actor, action=action, detail=detail, prev_hash=prev,
                       hash=_entry_hash(prev, ts.isoformat(), actor, action, detail))
    db.add(entry)
    db.flush()
    head = db.get(AuditHead, 1) or AuditHead(id=1)
    head.last_id, head.last_hash = entry.id, entry.hash
    head.mac = _mac(_key(db), entry.id, entry.hash)
    db.add(head)
    db.flush()


def verify_chain(db: Session) -> bool:
    """True when no entry was altered, and none removed from the middle or the
    end. The oldest surviving entry anchors the start, so retention purges stay
    valid; the signed head pins the end.

    An attacker holding both the database and the signing key could rewrite
    everything, so ship the head hash regularly to a separate append-only store
    (see docs/SECURITY.md)."""
    rows = db.execute(select(AuditEntry).order_by(AuditEntry.id)).scalars().all()
    head = db.get(AuditHead, 1)
    expected_prev = None
    for r in rows:
        if expected_prev is not None and r.prev_hash != expected_prev:
            return False
        if _entry_hash(r.prev_hash, r.ts.isoformat(), r.actor, r.action, r.detail) != r.hash:
            return False
        expected_prev = r.hash
    if not rows:
        return head is None
    if head is None:
        return False
    if not hmac.compare_digest(head.mac, _mac(_key(db), head.last_id, head.last_hash)):
        return False
    return head.last_id == rows[-1].id and head.last_hash == rows[-1].hash


def head_hash(db: Session) -> str | None:
    """The value to ship to the external log store."""
    head = db.get(AuditHead, 1)
    return None if head is None else f"{head.last_id}:{head.last_hash}"
