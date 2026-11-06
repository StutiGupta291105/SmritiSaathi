"""Report button, privacy policy and account-deletion pages (Google Play requirements)."""
from app.models import Report

PHONE_P, PHONE_C = "+919876543210", "+919811111111"


def test_report_an_ai_answer_and_a_chat_message(env):
    a, pid = env.make_patient(PHONE_P)
    r = env.client.post("/v1/reports", headers=a.headers,
                        json={"kind": "ai", "excerpt": "a bad answer", "reason": "unsafe"})
    assert r.status_code == 201
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    assert env.client.post("/v1/reports", headers=cg.headers,
                           json={"kind": "chat", "ref": "12", "excerpt": "rude"}).status_code == 201
    with env.app.state.sessionmaker() as db:
        rows = db.query(Report).order_by(Report.id).all()
        assert [(x.kind, x.ref, x.excerpt) for x in rows] == [("ai", "", "a bad answer"), ("chat", "12", "rude")]
    # the audit log notes it, without the content
    assert env.client.post("/v1/reports", json={"kind": "ai"}).status_code in (401, 403)


def test_report_validation_and_daily_limit(env):
    a, _ = env.make_patient(PHONE_P)
    assert env.client.post("/v1/reports", headers=a.headers, json={"kind": "spam"}).status_code == 422
    assert env.client.post("/v1/reports", headers=a.headers,
                           json={"kind": "ai", "excerpt": "x" * 501}).status_code == 422
    for _ in range(20):
        assert env.client.post("/v1/reports", headers=a.headers, json={"kind": "ai"}).status_code == 201
    assert env.client.post("/v1/reports", headers=a.headers, json={"kind": "ai"}).status_code == 429


def test_reports_are_deleted_with_the_account(env):
    a, pid = env.make_patient(PHONE_P)
    env.client.post("/v1/reports", headers=a.headers, json={"kind": "ai", "excerpt": "x"})
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    with env.app.state.sessionmaker() as db:
        assert db.query(Report).count() == 0


def test_public_policy_and_deletion_pages(env):
    p = env.client.get("/privacy")
    assert p.status_code == 200 and "privacy policy" in p.text.lower()
    flat = " ".join(p.text.split())
    for must in ("Location", "AI helper", "erase", "not a medical device", "Children"):
        assert must in flat
    d = env.client.get("/delete-account")
    assert d.status_code == 200 and "Erase my data" in d.text
    assert "<script" not in p.text.lower() and "<script" not in d.text.lower()


def test_contact_email_is_shown_and_escaped():
    from tests.conftest import Env
    e = Env(contact_email='help@example.com"><b>')
    t = e.client.get("/privacy").text
    assert "mailto:help@example.com&quot;&gt;&lt;b&gt;" in t and "<b>" not in t.split("Contact:")[-1][:80]
