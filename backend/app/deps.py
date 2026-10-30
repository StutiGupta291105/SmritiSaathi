
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWTError
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import audit
from .config import Settings
from .models import (ROLE_PURPOSE, AdminUser, Consent, Link, Patient, User)
from .security import decode_access_token, decode_admin_token, keyed_hash

bearer = HTTPBearer(auto_error=False)


def settings_of(request: Request) -> Settings:
    return request.app.state.settings


def get_db(request: Request):
    """One transaction per request: committed on success, rolled back on any
    error. Handlers that must keep a change even when they then reject the
    request (counting a wrong OTP, say) commit explicitly before raising."""
    db: Session = request.app.state.sessionmaker()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def client_ip(request: Request) -> str:
    s = settings_of(request)
    if s.trust_proxy:
        fwd = request.headers.get("x-forwarded-for", "")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def ip_hash(request: Request) -> str:
    """IPs are only ever stored keyed-hashed, for rate limiting."""
    return keyed_hash(client_ip(request), settings_of(request).phone_hmac_key)


def current_user(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if creds is None:
        raise HTTPException(401, "not_authenticated")
    try:
        claims = decode_access_token(creds.credentials, settings_of(request))
    except PyJWTError:
        raise HTTPException(401, "invalid_token")
    user = db.get(User, claims["sub"])
    if user is None:
        raise HTTPException(401, "invalid_token")
    return user


def require_role(*roles: str):
    def dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, "wrong_role")
        return user
    return dep


# ---- access control --------------------------------------------------------

def consent_granted(db: Session, patient_id: str, purpose: str) -> bool:
    """The newest decision for the purpose wins (withdrawal = a newer 'no')."""
    row = db.execute(
        select(Consent.granted)
        .where(Consent.patient_id == patient_id, Consent.purpose == purpose)
        .order_by(Consent.id.desc()).limit(1)
    ).scalar_one_or_none()
    return bool(row)


def patient_or_404(db: Session, patient_id: str) -> Patient:
    p = db.get(Patient, patient_id)
    if p is None:
        raise HTTPException(404, "not_found")
    return p


def accepted_link(db: Session, user: User, patient_id: str) -> Link | None:
    return db.execute(
        select(Link).where(
            Link.patient_id == patient_id,
            Link.member_user_id == user.id,
            Link.member_role == user.role,
            Link.status == "accepted",
        )
    ).scalar_one_or_none()


def patient_for_owner(db: Session, user: User, patient_id: str) -> Patient:
    """The patient's own account only. Anything else looks like 'not found' so
    IDs cannot be probed."""
    p = patient_or_404(db, patient_id)
    if user.role != "patient" or p.user_id != user.id:
        raise HTTPException(404, "not_found")
    return p


def patient_for_viewer(db: Session, user: User, patient_id: str) -> tuple[Patient, str]:
    """The patient, or a linked caretaker/doctor whose link is accepted AND for
    whom the patient's matching sharing consent is currently granted. Returns
    (patient, 'owner' | 'member')."""
    p = patient_or_404(db, patient_id)
    if user.role == "patient":
        if p.user_id != user.id:
            raise HTTPException(404, "not_found")
        return p, "owner"
    link = accepted_link(db, user, patient_id)
    purpose = ROLE_PURPOSE.get(user.role)
    if link is None or purpose is None or not consent_granted(db, patient_id, purpose):
        # Kept even though the request fails: a caretaker or doctor reaching for a
        # patient they are not (or no longer) linked to is what a security review
        # wants to see. Only ids are recorded.
        audit.record(db, user.id, "access_denied", f"patient={patient_id} role={user.role}")
        db.commit()
        raise HTTPException(404, "not_found")
    return p, "member"


def current_admin(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> AdminUser:
    if creds is None:
        raise HTTPException(401, "not_authenticated")
    try:
        claims = decode_admin_token(creds.credentials, settings_of(request))
    except PyJWTError:
        raise HTTPException(401, "invalid_token")
    admin = db.get(AdminUser, claims["sub"])
    if admin is None or admin.disabled:
        raise HTTPException(401, "invalid_token")
    return admin
