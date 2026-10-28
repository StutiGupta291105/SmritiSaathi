import hashlib
import hmac
import re
import secrets
from datetime import datetime, timedelta, timezone

import jwt

from .config import Settings

PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")
AUDIENCE = "smriti-sathi"


def normalize_phone(raw: str) -> str | None:
    """E.164 only. The app sends E.164; anything else is rejected."""
    cleaned = re.sub(r"[\s\-().]", "", raw or "")
    return cleaned if PHONE_RE.match(cleaned) else None


def keyed_hash(value: str, key: str) -> str:
    return hmac.new(key.encode(), value.encode(), hashlib.sha256).hexdigest()


def phone_hmac(phone: str, s: Settings) -> str:
    """Lookup key for a phone number. The number itself is never stored."""
    return keyed_hash(phone, s.phone_hmac_key)


def new_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def otp_hash(code: str, challenge_id: str, s: Settings) -> str:
    return keyed_hash(f"{challenge_id}:{code}", s.secret_key)


def constant_time_equal(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def refresh_hash(token: str, s: Settings) -> str:
    return keyed_hash(token, s.secret_key)


def make_access_token(user_id: str, role: str, s: Settings) -> str:
    now = datetime.now(timezone.utc)  # real UTC, not naive, so timestamps are right
    payload = {
        "sub": user_id,
        "role": role,
        "aud": AUDIENCE,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=s.access_ttl_minutes)).timestamp()),
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(payload, s.secret_key, algorithm="HS256")


def decode_access_token(token: str, s: Settings) -> dict:
    return jwt.decode(
        token, s.secret_key, algorithms=["HS256"], audience=AUDIENCE,
        options={"require": ["exp", "sub", "aud", "iat"]},
    )
