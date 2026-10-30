import base64
import hashlib
import hmac
import re
import secrets
import struct
import time
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


_CARE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O/1/I/L
CARE_ID_PATTERN = re.compile(r"^(CG|DR)-[A-HJKMNP-Z2-9]{6}$")
_CARE_PREFIX = {"caretaker": "CG", "doctor": "DR"}


def new_care_id(role: str) -> str:
    """An ID a patient types to invite a caretaker ('CG-') or doctor ('DR-')."""
    return _CARE_PREFIX[role] + "-" + "".join(
        secrets.choice(_CARE_ALPHABET) for _ in range(6))


def clean_care_id(raw: str) -> str | None:
    """Upper-cased and checked, or None when it is not shaped like a care ID."""
    cid = raw.strip().upper().replace(" ", "")
    return cid if CARE_ID_PATTERN.match(cid) else None


def role_of_care_id(cid: str) -> str:
    return "doctor" if cid.startswith("DR-") else "caretaker"


# ---- admin portal accounts ----------------------------------------------------
ADMIN_AUDIENCE = "smriti-sathi-admin"  # a different audience: an app token never opens the portal, nor the reverse
_PBKDF2_ROUNDS = 240_000


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ROUNDS)
    return f"pbkdf2${_PBKDF2_ROUNDS}${salt.hex()}${dk.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, rounds, salt, dk = stored.split("$")
        got = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), int(rounds))
        return hmac.compare_digest(got.hex(), dk)
    except Exception:
        return False


def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp_code(secret: str, at: float | None = None, step: int = 30) -> str:
    """RFC 6238 (SHA-1, 6 digits), the one every authenticator app uses."""
    key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    counter = int((time.time() if at is None else at) // step)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    o = mac[-1] & 0x0F
    return f"{(struct.unpack('>I', mac[o:o + 4])[0] & 0x7FFFFFFF) % 1_000_000:06d}"


def totp_ok(secret: str, code: str, at: float | None = None) -> bool:
    now = time.time() if at is None else at
    return any(hmac.compare_digest(totp_code(secret, now + d * 30), (code or "").strip())
               for d in (-1, 0, 1))


def admin_password_ok(password: str, s: Settings) -> bool:
    if s.admin_password_hash:
        return verify_password(password, s.admin_password_hash)
    return bool(s.admin_password) and constant_time_equal(password, s.admin_password)


def make_admin_token(admin_id: str, s: Settings) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": admin_id, "aud": ADMIN_AUDIENCE, "iat": int(now.timestamp()),
                       "exp": int((now + timedelta(minutes=30)).timestamp()),
                       "jti": secrets.token_hex(8)}, s.secret_key, algorithm="HS256")


def decode_admin_token(token: str, s: Settings) -> dict:
    return jwt.decode(token, s.secret_key, algorithms=["HS256"], audience=ADMIN_AUDIENCE,
                      options={"require": ["exp", "sub", "aud", "iat"]})
