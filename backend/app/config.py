"""Settings come from environment variables (prefix SMRITI_). In production
(SMRITI_ENV=prod) the secrets must be set explicitly; the app refuses to start
with development defaults."""
import os
from dataclasses import dataclass

_DEV_SECRET = "dev-only-secret-change-me-dev-only-secret"
_DEV_PHONE_KEY = "dev-only-phone-key-change-me-dev-only"


FIXED_TEST_OTP = "123456"  # only with SMRITI_SMS_PROVIDER=test, which prod refuses


@dataclass(frozen=True)
class Settings:
    env: str = "dev"
    database_url: str = "sqlite:///./smriti_dev.db"
    secret_key: str = _DEV_SECRET          # signs access tokens
    phone_hmac_key: str = _DEV_PHONE_KEY   # keyed hash for phone lookups
    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5
    otp_requests_per_hour_phone: int = 5
    otp_requests_per_hour_ip: int = 20
    access_ttl_minutes: int = 15
    refresh_ttl_days: int = 30
    requests_per_minute_ip: int = 120
    max_body_bytes: int = 1_000_000
    sms_provider: str = "dev"                  # "dev", "test" (fixed code, never in prod) or a real one
    push_provider: str = "dev"                 # "dev" or "fcm"
    companion_provider: str = "dev"            # "dev", "anthropic" or "openai_compat" (Gemini, Groq...)
    companion_model: str = "claude-opus-5-5"   # any Claude model id; cheaper ones cost less
    companion_daily_limit: int = 40            # answered messages per patient per day
    companion_style: str = "assistant"         # "assistant" (general helper) or "companion" (chat only)
    trust_proxy: bool = False  # true only behind a proxy you control (X-Forwarded-For)
    # The one admin of the read-only admin portal. Fixed in the server's settings, not
    # a user account: it is not in the users table and cannot be created or changed
    # through any API. Unset password and hash = the admin portal is switched off.
    admin_username: str = "admin"
    admin_password: str = ""           # simplest: the password itself (kept in the host's secret store)
    admin_password_hash: str = ""      # or a hash made with: python -m app.cli admin-hash
    admin_totp_secret: str = ""        # optional authenticator-app secret (a second factor)

    @property
    def is_prod(self) -> bool:
        return self.env == "prod"

    @property
    def admin_enabled(self) -> bool:
        return bool(self.admin_username and (self.admin_password or self.admin_password_hash))


def load_settings() -> Settings:
    def g(name: str, default):
        raw = os.environ.get(f"SMRITI_{name}")
        if raw is None:
            return default
        if isinstance(default, bool):
            return raw.strip().lower() in ("1", "true", "yes")
        return type(default)(raw)

    d = Settings()
    db_url = g("DATABASE_URL", d.database_url)
    # Hosts such as Render hand out plain postgres:// or postgresql:// URLs.
    for plain in ("postgres://", "postgresql://"):
        if db_url.startswith(plain):
            db_url = "postgresql+psycopg://" + db_url[len(plain):]
    s = Settings(
        env=g("ENV", d.env),
        database_url=db_url,
        secret_key=g("SECRET_KEY", d.secret_key),
        phone_hmac_key=g("PHONE_HMAC_KEY", d.phone_hmac_key),
        otp_ttl_seconds=g("OTP_TTL_SECONDS", d.otp_ttl_seconds),
        otp_max_attempts=g("OTP_MAX_ATTEMPTS", d.otp_max_attempts),
        otp_requests_per_hour_phone=g("OTP_PER_HOUR_PHONE", d.otp_requests_per_hour_phone),
        otp_requests_per_hour_ip=g("OTP_PER_HOUR_IP", d.otp_requests_per_hour_ip),
        access_ttl_minutes=g("ACCESS_TTL_MINUTES", d.access_ttl_minutes),
        refresh_ttl_days=g("REFRESH_TTL_DAYS", d.refresh_ttl_days),
        requests_per_minute_ip=g("REQUESTS_PER_MINUTE_IP", d.requests_per_minute_ip),
        max_body_bytes=g("MAX_BODY_BYTES", d.max_body_bytes),
        sms_provider=g("SMS_PROVIDER", d.sms_provider),
        push_provider=g("PUSH_PROVIDER", d.push_provider),
        companion_provider=g("COMPANION_PROVIDER", d.companion_provider),
        companion_model=g("COMPANION_MODEL", d.companion_model),
        companion_daily_limit=g("COMPANION_DAILY_LIMIT", d.companion_daily_limit),
        companion_style=g("COMPANION_STYLE", d.companion_style),
        trust_proxy=g("TRUST_PROXY", d.trust_proxy),
        admin_username=g("ADMIN_USERNAME", d.admin_username).strip().lower(),
        admin_password=g("ADMIN_PASSWORD", d.admin_password),
        admin_password_hash=g("ADMIN_PASSWORD_HASH", d.admin_password_hash),
        admin_totp_secret=g("ADMIN_TOTP_SECRET", d.admin_totp_secret),
    )
    if s.is_prod:
        problems = []
        if s.secret_key == _DEV_SECRET or len(s.secret_key) < 32:
            problems.append("SMRITI_SECRET_KEY must be set (32+ characters)")
        if s.phone_hmac_key == _DEV_PHONE_KEY or len(s.phone_hmac_key) < 32:
            problems.append("SMRITI_PHONE_HMAC_KEY must be set (32+ characters)")
        if s.sms_provider in ("dev", "test"):
            problems.append("SMRITI_SMS_PROVIDER must be a real provider in prod")
        if s.database_url.startswith("sqlite"):
            problems.append("SMRITI_DATABASE_URL must be PostgreSQL in prod")
        if s.companion_provider == "openai_compat" and not os.environ.get("SMRITI_COMPANION_API_KEY"):
            problems.append("SMRITI_COMPANION_API_KEY must be set when the companion uses openai_compat")
        if s.companion_provider == "anthropic" and not os.environ.get("ANTHROPIC_API_KEY"):
            problems.append("ANTHROPIC_API_KEY must be set when the companion uses anthropic")
        if s.admin_password and len(s.admin_password) < 12:
            problems.append("SMRITI_ADMIN_PASSWORD must be 12+ characters")
        if problems:
            raise RuntimeError("Unsafe production configuration: " + "; ".join(problems))
    return s
