"""The admin portal API: who is in the system, who supervises whom, the access log.
It is read only, and it never shows what people said or wrote."""
import json

import pytest

from app.security import hash_password, new_totp_secret, totp_code
from tests.conftest import Env
from tests.test_care import session_payload

P, C, D = "+919876543210", "+919811111111", "+919822222222"
PASSWORD = "correct horse battery"


SECRET = new_totp_secret()


@pytest.fixture
def env():
    """An environment where the one fixed admin is configured."""
    return Env(admin_username="admin", admin_password=PASSWORD, admin_totp_secret=SECRET)


def _login(env, secret=None, **over):
    body = {"username": "admin", "password": PASSWORD, "code": totp_code(secret or SECRET)}
    body.update(over)
    return env.client.post("/v1/admin/login", json=body)


def _headers(env, secret=None):
    r = _login(env, secret)
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _family(env):
    a, pid = env.make_patient(P, "Asha Devi", consents=("gameplay", "reminders", "sync"))
    cg = env.link_member(a, pid, "caretaker", C)
    dr = env.link_member(a, pid, "doctor", D)
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={"sessions": [session_payload(1)]})
    env.client.post(f"/v1/chat/{env.client.get('/v1/chat/threads', headers=a.headers).json()[0]['link_id']}/messages",
                    headers=a.headers, json={"kind": "text", "text": "PRIVATE-CHAT-TEXT"})
    env.client.post(f"/v1/patients/{pid}/care-reminders", headers=dr.headers,
                    json={"kind": "medicine", "label": "PRIVATE-MEDICINE", "hour": 9, "minute": 0})
    return a, pid, cg, dr


def test_one_fixed_admin_signs_in_with_password_and_code_and_a_bad_address_is_locked(env):
    assert _login(env).status_code == 200
    assert _login(env, password="wrong password!!").status_code == 401
    assert _login(env, code="000000").status_code == 401
    assert _login(env, username="nobody").status_code == 401
    assert _login(env, username="ADMIN ").status_code == 200  # same account, case and spaces ignored
    for _ in range(5):
        _login(env, password="wrong password!!")
    assert _login(env).status_code == 429  # locked, even with the right details


def test_password_only_when_no_authenticator_secret_is_configured():
    e = Env(admin_password=PASSWORD)
    r = e.client.post("/v1/admin/login", json={"username": "admin", "password": PASSWORD})
    assert r.status_code == 200


def test_a_stored_hash_works_instead_of_the_plain_password():
    e = Env(admin_password_hash=hash_password(PASSWORD))
    ok = e.client.post("/v1/admin/login", json={"username": "admin", "password": PASSWORD})
    bad = e.client.post("/v1/admin/login", json={"username": "admin", "password": "something else!!"})
    assert ok.status_code == 200 and bad.status_code == 401


def test_without_a_configured_password_the_portal_does_not_exist():
    e = Env()
    assert e.client.post("/v1/admin/login", json={"username": "admin", "password": "x" * 12}).status_code == 404
    assert e.client.get("/v1/admin/overview").status_code == 404
    assert not any(p.startswith("/v1/admin") for p in e.client.app.openapi()["paths"])


def test_the_admin_is_not_a_user_account(env):
    from sqlalchemy import select
    from app.models import User
    _headers(env)
    with env.client.app.state.sessionmaker() as s:
        assert s.execute(select(User)).scalars().all() == []
    # the app's own sign-in has no admin role, and the portal has no way to make one
    assert env.request_otp("+919876543210", "admin").status_code == 422


def test_short_plain_passwords_are_refused_in_production(monkeypatch):
    from app.config import load_settings
    for k, v in {"ENV": "prod", "SECRET_KEY": "s" * 40, "PHONE_HMAC_KEY": "p" * 40, "SMS_PROVIDER": "real",
                 "DATABASE_URL": "postgresql://u:p@h/db", "ADMIN_PASSWORD": "short"}.items():
        monkeypatch.setenv(f"SMRITI_{k}", v)
    with pytest.raises(RuntimeError, match="ADMIN_PASSWORD"):
        load_settings()


def test_tokens_are_not_interchangeable(env):
    a, pid, cg, dr = _family(env)
    h = _headers(env)
    assert env.client.get("/v1/admin/overview", headers=a.headers).status_code == 401  # an app token
    assert env.client.get(f"/v1/patients/{pid}/report", headers=h).status_code == 401  # an admin token
    assert env.client.get("/v1/admin/overview").status_code == 401


def test_every_admin_route_is_read_only(env):
    paths = env.client.app.openapi()["paths"]
    admin = {p: set(m) for p, m in paths.items() if p.startswith("/v1/admin")}
    assert len(admin) >= 8
    writing = [(p, m - {"get"}) for p, m in admin.items() if m - {"get"}]
    assert writing == [("/v1/admin/login", {"post"})]
    h = _headers(env)
    for method in ("post", "put", "patch", "delete"):
        r = getattr(env.client, method)("/v1/admin/users", headers=h)
        assert r.status_code == 405


def test_admin_cannot_change_anything_in_the_app(env):
    a, pid, cg, dr = _family(env)
    h = _headers(env)
    before = env.client.get("/v1/admin/overview", headers=h).json()
    for method, url, body in [("post", f"/v1/patients/{pid}/consents", {"consents": []}),
                              ("patch", f"/v1/patients/{pid}/baseline", {"baseline_level": 5}),
                              ("delete", f"/v1/patients/{pid}", None),
                              ("post", f"/v1/patients/{pid}/care-reminders", {"kind": "event", "hour": 1, "minute": 1})]:
        kw = {"json": body} if body is not None else {}
        assert getattr(env.client, method)(url, headers=h, **kw).status_code == 401, url
    after = env.client.get("/v1/admin/overview", headers=h).json()
    assert before["users"] == after["users"] and before["links"] == after["links"]


def test_overview_people_and_who_supervises_whom(env):
    a, pid, cg, dr = _family(env)
    h = _headers(env)
    ov = env.client.get("/v1/admin/overview", headers=h).json()
    assert ov["users"] == {"patient": 1, "doctor": 1, "caretaker": 1}
    assert ov["links"]["accepted"] == 2 and ov["patients_without_supervisor"] == 0
    assert ov["doctors_unverified"] == 1 and ov["sessions_24h"] == 1 and ov["messages_24h"] == 1

    docs = env.client.get("/v1/admin/users?role=doctor", headers=h).json()
    assert docs["total"] == 1 and docs["items"][0]["care_id"].startswith("DR-")
    assert docs["items"][0]["patients"] == 1 and docs["items"][0]["last_login_at"]
    assert env.client.get("/v1/admin/users?q=Asha", headers=h).json()["total"] == 1

    pats = env.client.get("/v1/admin/patients", headers=h).json()["items"]
    assert len(pats) == 1
    p = pats[0]
    assert p["name"] == "Asha Devi" and p["phone_last4"] == "3210"
    assert [x["name"] for x in p["doctors"]] == ["Member"] and [x["name"] for x in p["caregivers"]] == ["Member"]
    assert p["sessions"] == 1 and p["sharing"]["doctor"] and p["sharing"]["caregiver"]

    links = env.client.get("/v1/admin/links?status=accepted", headers=h).json()
    assert links["total"] == 2
    assert {(l["member_role"], l["patient_name"]) for l in links["items"]} == {
        ("doctor", "Asha Devi"), ("caretaker", "Asha Devi")}
    assert sum(l["message_count"] for l in links["items"]) == 1

    # a doctor's page lists the patients they look after; a patient's lists the supervisors
    d = env.client.get(f"/v1/admin/users/{dr.user['id']}", headers=h).json()
    assert [x["patient_name"] for x in d["patients"]] == ["Asha Devi"] and d["care_reminders_set"] == 1
    pu = env.client.get(f"/v1/admin/users/{a.user['id']}", headers=h).json()
    assert {x["member_role"] for x in pu["supervisors"]} == {"doctor", "caretaker"}
    assert pu["patient"]["consents"]["doctor_share"]["granted"] is True
    assert pu["patient"]["care_reminders"] == 1
    assert env.client.get("/v1/admin/users/nope", headers=h).status_code == 404


def test_the_portal_never_shows_what_people_said_or_wrote(env):
    a, pid, cg, dr = _family(env)
    h = _headers(env)
    blob = ""
    for url in ["/v1/admin/overview", "/v1/admin/users", "/v1/admin/patients", "/v1/admin/links",
                f"/v1/admin/users/{a.user['id']}", f"/v1/admin/users/{dr.user['id']}",
                "/v1/admin/audit", "/v1/admin/security"]:
        r = env.client.get(url, headers=h)
        assert r.status_code == 200, url
        blob += json.dumps(r.json())
    assert "PRIVATE-CHAT-TEXT" not in blob and "PRIVATE-MEDICINE" not in blob
    assert "phone_hmac" not in blob and "password" not in blob


def test_access_log_records_logins_views_and_denied_attempts(env):
    a, pid, cg, dr = _family(env)
    env.login(C, "caretaker")
    stranger = env.signup("+919844444444", "caretaker", "Snoop")
    assert env.client.get(f"/v1/patients/{pid}/report", headers=stranger.headers).status_code == 404
    h = _headers(env)
    env.client.get(f"/v1/admin/users/{a.user['id']}", headers=h)
    log = env.client.get("/v1/admin/audit?limit=500", headers=h).json()
    actions = {e["action"] for e in log["items"]}
    assert {"login", "signup", "access_denied", "admin_login", "admin_viewed_user", "sync"} <= actions
    denied = [e for e in log["items"] if e["action"] == "access_denied"]
    assert denied[0]["actor_name"] == "Snoop (caretaker)" and f"patient={pid}" in denied[0]["detail"]
    only = env.client.get("/v1/admin/audit?action=access_denied", headers=h).json()
    assert only["total"] == 1
    sec = env.client.get("/v1/admin/security", headers=h).json()
    assert sec["last_24h"]["access_denied"] == 1
    assert any(e["action"] == "access_denied" for e in sec["recent_events"])
    ver = env.client.get("/v1/admin/audit/verify", headers=h).json()
    assert ver["ok"] is True and ver["entries"] > 5


def test_failed_admin_sign_ins_are_logged(env):
    _login(env, password="wrong password!!")
    h = _headers(env)
    sec = env.client.get("/v1/admin/security", headers=h).json()
    assert sec["last_24h"]["admin_login_failed"] == 1


def test_cli_makes_a_hash_for_the_settings(monkeypatch, capsys):
    from app import cli
    monkeypatch.setenv("SMRITI_ADMIN_PASSWORD_INPUT", PASSWORD)
    assert cli._admin_hash() == 0
    out = capsys.readouterr().out
    h = out.split("SMRITI_ADMIN_PASSWORD_HASH=")[1].split()[0]
    e = Env(admin_password_hash=h)
    assert e.client.post("/v1/admin/login", json={"username": "admin", "password": PASSWORD}).status_code == 200
    monkeypatch.setenv("SMRITI_ADMIN_PASSWORD_INPUT", "short")
    assert cli._admin_hash() == 1
