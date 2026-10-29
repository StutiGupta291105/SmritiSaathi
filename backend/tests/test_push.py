from app import dispatch
from app.push import DevPush
from tests.conftest import Env
from tests.test_care import iso, now, session_payload

TOKEN = "t" * 40


def old_sessions(env, a, pid):
    """Six games, all five days ago: triggers the 'inactive' attention alert."""
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={
        "sessions": [session_payload(i, minutes_ago=5 * 24 * 60 + i) for i in range(6)]})


def register(env, who, token=TOKEN):
    return env.client.post("/v1/devices", headers=who.headers,
                           json={"token": token, "platform": "android"})


def run(env, provider):
    with env.app.state.sessionmaker() as db:
        n = dispatch.send_pending_alerts(db, provider)
        db.commit()
    return n


def setup(consents=("gameplay", "sync")):
    env = Env()
    a, pid = env.make_patient(consents=consents)
    old_sessions(env, a, pid)
    return env, a, pid


def test_device_registration_validation_and_moving_between_accounts():
    env, a, pid = setup()
    m = env.link_member(a, pid, "caretaker")
    assert register(env, m).status_code == 204
    assert register(env, m).status_code == 204  # idempotent
    assert env.client.post("/v1/devices", headers=m.headers,
                           json={"token": "short"}).status_code == 422
    assert env.client.post("/v1/devices", json={"token": TOKEN}).status_code == 401
    # the same phone signs in as someone else: the token moves, never duplicates
    register(env, a)
    from sqlalchemy import text
    with env.app.state.engine.connect() as c:
        rows = c.execute(text("select user_id from device_tokens")).fetchall()
    assert rows == [(a.user["id"],)]
    assert env.client.request("DELETE", "/v1/devices", headers=m.headers,
                              json={"token": TOKEN}).status_code == 204  # not theirs: no effect
    with env.app.state.engine.connect() as c:
        assert c.execute(text("select count(*) from device_tokens")).scalar() == 1


def test_one_generic_push_per_alert_per_day():
    env, a, pid = setup()
    m = env.link_member(a, pid, "caretaker")
    register(env, m)
    dev = DevPush()
    assert run(env, dev) == 1
    token, title, body = dev.outbox[0]
    assert token == TOKEN and "Asha" in body
    assert "played" not in body.lower() and "inactive" not in body.lower()  # no detail on a lock screen
    assert run(env, dev) == 0 and len(dev.outbox) == 1                       # not again today


def test_no_push_without_sharing_consent_or_token_or_accepted_link():
    env, a, pid = setup()
    m = env.link_member(a, pid, "caretaker")
    dev = DevPush()
    assert run(env, dev) == 0                                   # no device registered
    register(env, m)
    env.consent(a, pid, "caregiver_share", False)               # withdrawn
    assert run(env, dev) == 0 and dev.outbox == []

    env2, a2, pid2 = setup()
    env2.consent(a2, pid2, "caregiver_share", True)
    env2.invite(a2, pid2, "caretaker", "+919811111111")         # invited, never accepted
    assert run(env2, DevPush()) == 0


def test_dead_tokens_are_removed_and_live_ones_still_get_it():
    env, a, pid = setup()
    m = env.link_member(a, pid, "caretaker")
    register(env, m, "dead" + "d" * 36)
    register(env, m, "live" + "l" * 36)
    dev = DevPush()
    dev.dead.add("dead" + "d" * 36)
    assert run(env, dev) == 1
    assert [t for t, *_ in dev.outbox] == ["live" + "l" * 36]
    from sqlalchemy import text
    with env.app.state.engine.connect() as c:
        left = [r[0] for r in c.execute(text("select token from device_tokens"))]
    assert left == ["live" + "l" * 36]


def test_a_failed_send_is_retried_next_run():
    env, a, pid = setup()
    m = env.link_member(a, pid, "caretaker")
    register(env, m)

    class Flaky:
        n = 0
        def send(self, token, title, body):
            self.n += 1
            return "failed" if self.n == 1 else "ok"

    f = Flaky()
    assert run(env, f) == 0
    assert run(env, f) == 1


def test_doctor_gets_it_too_and_a_calm_patient_triggers_nothing():
    env, a, pid = setup(consents=("gameplay", "sync"))
    d = env.link_member(a, pid, "doctor", "+919822222222")
    register(env, d)
    assert run(env, DevPush()) == 1

    env2 = Env()
    a2, pid2 = env2.make_patient(consents=("gameplay", "sync"))
    env2.client.post(f"/v1/patients/{pid2}/sync", headers=a2.headers,
                     json={"sessions": [session_payload(1)]})
    m2 = env2.link_member(a2, pid2, "caretaker")
    register(env2, m2)
    assert run(env2, DevPush()) == 0
