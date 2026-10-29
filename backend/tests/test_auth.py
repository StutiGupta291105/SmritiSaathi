import pytest
from sqlalchemy import text

from app.config import Settings, load_settings
from tests.conftest import Env

PHONE = "+919876543210"


def test_signup_then_login(env):
    a = env.signup(PHONE, "patient", "Asha")
    assert a.user["role"] == "patient"
    assert env.client.get("/v1/auth/me", headers=a.headers).json()["name"] == "Asha"
    b = env.login(PHONE, "patient")
    assert b.user["id"] == a.user["id"]


def test_invalid_phone_is_rejected(env):
    for bad in ["12345", "9876543210", "+0123456789", "abc", ""]:
        r = env.request_otp(bad, "patient")
        assert r.status_code == 422, bad


def test_request_answer_does_not_reveal_whether_an_account_exists(env):
    env.signup(PHONE, "patient")
    existing = env.request_otp(PHONE, "patient")
    unknown = env.request_otp("+919000000000", "patient")
    assert existing.status_code == unknown.status_code == 200
    assert existing.json().keys() == unknown.json().keys()


def test_login_without_account_only_says_so_after_a_valid_otp(env):
    ch = env.request_otp("+919000000001", "patient").json()["challenge_id"]
    wrong = env.verify(ch, "000000", "login")
    assert wrong.status_code == 400 and wrong.json()["detail"] == "otp_invalid"
    ok = env.verify(ch, env.last_code(), "login")
    assert ok.status_code == 404 and ok.json()["detail"] == "no_account"


def test_signup_for_an_existing_account_conflicts(env):
    env.signup(PHONE, "patient")
    ch = env.request_otp(PHONE, "patient").json()["challenge_id"]
    r = env.verify(ch, env.last_code(), "signup", "Again")
    assert r.status_code == 409


def test_same_number_can_hold_different_roles(env):
    env.signup(PHONE, "patient")
    env.signup(PHONE, "doctor", "Dr")


def test_code_works_once_only(env):
    ch = env.request_otp(PHONE, "patient").json()["challenge_id"]
    code = env.last_code()
    assert env.verify(ch, code, "signup", "A").status_code == 200
    assert env.verify(ch, code, "login").status_code == 400


def test_wrong_codes_lock_the_challenge_even_for_the_right_code(env):
    ch = env.request_otp(PHONE, "patient").json()["challenge_id"]
    code = env.last_code()
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(4):
        assert env.verify(ch, wrong, "signup", "A").status_code == 400
    assert env.verify(ch, wrong, "signup", "A").status_code == 429
    assert env.verify(ch, code, "signup", "A").status_code == 429


def test_expired_code_is_rejected():
    e = Env(otp_ttl_seconds=0)
    ch = e.request_otp(PHONE, "patient").json()["challenge_id"]
    assert e.verify(ch, e.last_code(), "signup", "A").status_code == 400


def test_otp_requests_are_limited_per_phone():
    e = Env(otp_requests_per_hour_phone=3)
    for _ in range(3):
        assert e.request_otp(PHONE, "patient").status_code == 200
    assert e.request_otp(PHONE, "patient").status_code == 429
    assert e.request_otp("+919000000002", "patient").status_code == 200


def test_otp_requests_are_limited_per_ip():
    e = Env(otp_requests_per_hour_ip=2)
    assert e.request_otp("+919000000003", "patient").status_code == 200
    assert e.request_otp("+919000000004", "patient").status_code == 200
    assert e.request_otp("+919000000005", "patient").status_code == 429


def test_refresh_rotates_and_reuse_ends_every_session(env):
    a = env.signup(PHONE, "patient")
    r1 = env.client.post("/v1/auth/refresh", json={"refresh_token": a.refresh})
    assert r1.status_code == 200
    new_refresh = r1.json()["refresh_token"]
    assert new_refresh != a.refresh
    # Presenting the old one again looks like theft: everything is revoked.
    again = env.client.post("/v1/auth/refresh", json={"refresh_token": a.refresh})
    assert again.status_code == 401
    assert env.client.post("/v1/auth/refresh",
                           json={"refresh_token": new_refresh}).status_code == 401


def test_logout_ends_the_refresh_token(env):
    a = env.signup(PHONE, "patient")
    assert env.client.post("/v1/auth/logout", json={"refresh_token": a.refresh}).status_code == 204
    assert env.client.post("/v1/auth/refresh",
                           json={"refresh_token": a.refresh}).status_code == 401


def test_bad_tokens_are_rejected(env):
    a = env.signup(PHONE, "patient")
    assert env.client.get("/v1/auth/me").status_code == 401
    assert env.client.get("/v1/auth/me",
                          headers={"Authorization": "Bearer nonsense"}).status_code == 401
    tampered = a.access[:-3] + ("abc" if not a.access.endswith("abc") else "xyz")
    assert env.client.get("/v1/auth/me",
                          headers={"Authorization": f"Bearer {tampered}"}).status_code == 401


def test_phone_numbers_are_never_stored_in_the_clear(env):
    env.signup(PHONE, "patient")
    env.signup("+919811111111", "caretaker")
    with env.app.state.engine.connect() as conn:
        tables = [r[0] for r in conn.execute(
            text("select name from sqlite_master where type='table'"))]
        for t in tables:
            dump = " ".join(str(row) for row in conn.execute(text(f"select * from {t}")))
            assert "9876543210" not in dump, t
            assert "9811111111" not in dump, t


def test_otp_codes_are_never_stored_in_the_clear(env):
    ch = env.request_otp(PHONE, "patient").json()["challenge_id"]
    code = env.last_code()
    with env.app.state.engine.connect() as conn:
        dump = " ".join(str(r) for r in conn.execute(text("select * from otp_challenges")))
    assert code not in dump.replace(ch, "")


def test_security_headers_and_no_caching(env):
    r = env.client.get("/healthz")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["cache-control"] == "no-store"
    assert "max-age" in r.headers["strict-transport-security"]


def test_oversized_bodies_are_refused():
    e = Env(max_body_bytes=200)
    r = e.client.post("/v1/auth/otp/request", content=b"x" * 500,
                      headers={"content-type": "application/json"})
    assert r.status_code == 413


def test_per_ip_request_limit():
    e = Env(requests_per_minute_ip=5)
    codes = [e.client.get("/healthz").status_code for _ in range(8)]
    assert codes[:5] == [200] * 5 and 429 in codes[5:]


def test_production_refuses_unsafe_defaults(monkeypatch):
    monkeypatch.setenv("SMRITI_ENV", "prod")
    with pytest.raises(RuntimeError) as err:
        load_settings()
    msg = str(err.value)
    assert "SECRET_KEY" in msg and "PHONE_HMAC_KEY" in msg
    assert "SMS_PROVIDER" in msg and "PostgreSQL" in msg


def test_production_accepts_a_safe_configuration(monkeypatch):
    monkeypatch.setenv("SMRITI_ENV", "prod")
    monkeypatch.setenv("SMRITI_SECRET_KEY", "k" * 40)
    monkeypatch.setenv("SMRITI_PHONE_HMAC_KEY", "p" * 40)
    monkeypatch.setenv("SMRITI_SMS_PROVIDER", "msg91")
    monkeypatch.setenv("SMRITI_DATABASE_URL", "postgresql+psycopg://u:p@h/db")
    assert load_settings().is_prod


def test_production_refuses_the_test_sms_provider(monkeypatch):
    monkeypatch.setenv("SMRITI_ENV", "prod")
    monkeypatch.setenv("SMRITI_SECRET_KEY", "k" * 40)
    monkeypatch.setenv("SMRITI_PHONE_HMAC_KEY", "p" * 40)
    monkeypatch.setenv("SMRITI_SMS_PROVIDER", "test")
    monkeypatch.setenv("SMRITI_DATABASE_URL", "postgresql+psycopg://u:p@h/db")
    with pytest.raises(RuntimeError, match="SMS_PROVIDER"):
        load_settings()


def test_host_style_database_urls_are_accepted(monkeypatch):
    for plain in ("postgres://u:p@h/db", "postgresql://u:p@h/db"):
        monkeypatch.setenv("SMRITI_DATABASE_URL", plain)
        assert load_settings().database_url == "postgresql+psycopg://u:p@h/db"


def test_test_provider_uses_the_fixed_code_and_sends_nothing(tmp_path):
    from fastapi.testclient import TestClient
    from app.main import create_app
    s = Settings(sms_provider="test", database_url=f"sqlite:///{tmp_path}/t.db")
    c = TestClient(create_app(s))
    r = c.post("/v1/auth/otp/request", json={"phone": PHONE, "role": "patient"})
    assert r.status_code == 200, r.text
    v = c.post("/v1/auth/otp/verify", json={
        "challenge_id": r.json()["challenge_id"], "code": "123456",
        "name": "Test Person", "mode": "signup"})
    assert v.status_code == 200, v.text
