from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .. import audit
from ..config import FIXED_TEST_OTP
from ..db import utcnow
from ..deps import current_user, get_db, ip_hash, require_role, settings_of
from ..models import OtpChallenge, RefreshToken, User, new_id
from ..schemas import (ContactIn, OtpRequest, OtpRequestOut, OtpVerify, RefreshIn,
                       TokenOut, UserOut)
from ..security import (constant_time_equal, make_access_token, new_care_id, new_otp,
                        new_refresh_token, normalize_phone, otp_hash,
                        phone_hmac, refresh_hash)

router = APIRouter(prefix="/v1/auth", tags=["auth"])


def ensure_care_id(db: Session, user: User) -> None:
    """Caretakers and doctors each get one ID, so a patient can invite them
    without anyone's phone number being shared."""
    if user.role == "patient" or user.care_id:
        return
    for _ in range(10):
        cid = new_care_id(user.role)
        if db.scalar(select(User.id).where(User.care_id == cid)) is None:
            user.care_id = cid
            db.flush()
            return
    raise HTTPException(500, "care_id_unavailable")


def _issue(db: Session, user: User, s) -> TokenOut:
    ensure_care_id(db, user)
    refresh = new_refresh_token()
    db.add(RefreshToken(
        user_id=user.id, token_hash=refresh_hash(refresh, s),
        expires_at=utcnow() + timedelta(days=s.refresh_ttl_days),
    ))
    return TokenOut(
        access_token=make_access_token(user.id, user.role, s),
        refresh_token=refresh,
        user=UserOut(id=user.id, role=user.role, name=user.name, care_id=user.care_id,
                     contact_phone=user.contact_phone),
    )


@router.post("/otp/request", response_model=OtpRequestOut)
def otp_request(body: OtpRequest, request: Request, db: Session = Depends(get_db)):
    """Sends a one-time code. The answer is identical whether or not an account
    exists for the number, so this cannot be used to find out who is registered."""
    s = settings_of(request)
    phone = normalize_phone(body.phone)
    if phone is None:
        raise HTTPException(422, "invalid_phone")
    ph, iph = phone_hmac(phone, s), ip_hash(request)

    since = utcnow() - timedelta(hours=1)
    by_phone = db.scalar(select(func.count()).select_from(OtpChallenge).where(
        OtpChallenge.phone_hmac == ph, OtpChallenge.created_at >= since))
    by_ip = db.scalar(select(func.count()).select_from(OtpChallenge).where(
        OtpChallenge.ip_hmac == iph, OtpChallenge.created_at >= since))
    if by_phone >= s.otp_requests_per_hour_phone or by_ip >= s.otp_requests_per_hour_ip:
        raise HTTPException(429, "too_many_requests")

    cid = new_id()
    code = FIXED_TEST_OTP if s.sms_provider == "test" else new_otp()
    db.add(OtpChallenge(
        id=cid, phone_hmac=ph, phone_last4=phone[-4:], role=body.role,
        code_hash=otp_hash(code, cid, s),
        expires_at=utcnow() + timedelta(seconds=s.otp_ttl_seconds), ip_hmac=iph,
    ))
    request.app.state.sms.send(
        phone,
        f"{code} is your Smriti Sathi code. Do not share it. "
        f"It is valid for {s.otp_ttl_seconds // 60} minutes.",
    )
    audit.record(db, "system", "otp_requested", f"challenge={cid}")
    return OtpRequestOut(challenge_id=cid, expires_in=s.otp_ttl_seconds)


@router.post("/otp/verify", response_model=TokenOut)
def otp_verify(body: OtpVerify, request: Request, db: Session = Depends(get_db)):
    s = settings_of(request)
    ch = db.get(OtpChallenge, body.challenge_id)
    if ch is None or ch.consumed or ch.expires_at < utcnow():
        raise HTTPException(400, "otp_invalid")
    if ch.attempts >= s.otp_max_attempts:
        raise HTTPException(429, "otp_locked")

    if not constant_time_equal(otp_hash(body.code, ch.id, s), ch.code_hash):
        ch.attempts += 1
        audit.record(db, "system", "otp_failed", f"challenge={ch.id} tries={ch.attempts}")
        locked = ch.attempts >= s.otp_max_attempts
        db.commit()  # keep the count even though we reject the request
        raise HTTPException(429 if locked else 400, "otp_locked" if locked else "otp_invalid")

    ch.consumed = True  # single use, whatever happens next
    user = db.execute(select(User).where(
        User.phone_hmac == ch.phone_hmac, User.role == ch.role)).scalar_one_or_none()

    if body.mode == "login":
        if user is None:
            db.commit()
            raise HTTPException(404, "no_account")  # only revealed after a valid OTP
        action = "login"
    else:
        if user is not None:
            db.commit()
            raise HTTPException(409, "account_exists")
        name = (body.name or "").strip()
        if not name:
            db.commit()
            raise HTTPException(422, "name_required")
        user = User(phone_hmac=ch.phone_hmac, phone_last4=ch.phone_last4,
                    role=ch.role, name=name)
        db.add(user)
        db.flush()
        action = "signup"

    audit.record(db, user.id, action, f"role={user.role}")
    return _issue(db, user, s)


@router.post("/refresh", response_model=TokenOut)
def refresh(body: RefreshIn, request: Request, db: Session = Depends(get_db)):
    """Rotates the refresh token. Presenting one that was already used means it
    may have been stolen, so every session of that user is ended."""
    s = settings_of(request)
    rt = db.execute(select(RefreshToken).where(
        RefreshToken.token_hash == refresh_hash(body.refresh_token, s))).scalar_one_or_none()
    if rt is None:
        raise HTTPException(401, "invalid_token")
    if rt.revoked:
        db.execute(update(RefreshToken).where(
            RefreshToken.user_id == rt.user_id).values(revoked=True))
        audit.record(db, rt.user_id, "refresh_reuse_detected", "all sessions ended")
        db.commit()
        raise HTTPException(401, "invalid_token")
    if rt.expires_at < utcnow():
        raise HTTPException(401, "invalid_token")
    user = db.get(User, rt.user_id)
    rt.revoked = True
    return _issue(db, user, s)


@router.post("/logout", status_code=204)
def logout(body: RefreshIn, request: Request, db: Session = Depends(get_db)):
    s = settings_of(request)
    rt = db.execute(select(RefreshToken).where(
        RefreshToken.token_hash == refresh_hash(body.refresh_token, s))).scalar_one_or_none()
    if rt is not None and not rt.revoked:
        rt.revoked = True
        audit.record(db, rt.user_id, "logout", "")


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    ensure_care_id(db, user)
    return UserOut(id=user.id, role=user.role, name=user.name, care_id=user.care_id,
                   contact_phone=user.contact_phone)


@router.put("/me/contact", response_model=UserOut)
def set_contact(body: ContactIn, user: User = Depends(require_role("caretaker", "doctor")),
                db: Session = Depends(get_db)):
    """A caretaker or doctor chooses whether their patients can call them from the
    app. An empty number turns it off."""
    raw = body.phone.strip()
    if raw:
        phone = normalize_phone(raw)
        if phone is None:
            raise HTTPException(422, "invalid_phone")
        user.contact_phone = phone
    else:
        user.contact_phone = None
    audit.record(db, user.id, "contact_phone_changed", f"shared={bool(user.contact_phone)}")
    return UserOut(id=user.id, role=user.role, name=user.name, care_id=user.care_id,
                   contact_phone=user.contact_phone)
