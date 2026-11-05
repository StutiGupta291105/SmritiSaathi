"""Live location: share, update, see, stop, expire, erase."""
from datetime import timedelta

from app.db import utcnow
from app.models import LiveShare

PHONE_P, PHONE_C, PHONE_D = "+919876543210", "+919811111111", "+919822222222"


def _start(env, a, minutes=60, lat=12.97, lng=77.59):
    return env.client.post("/v1/live/start", headers=a.headers,
                           json={"lat": lat, "lng": lng, "accuracy": 8, "minutes": minutes})


def test_start_update_view_stop(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    assert env.client.get(f"/v1/live/patient/{pid}", headers=cg.headers).json() == {"active": False}
    r = _start(env, a)
    assert r.status_code == 201
    link = r.json()["url"]
    assert "/live/" in link and r.json()["active"] is True
    # the caretaker sees the latest point
    seen = env.client.get(f"/v1/live/patient/{pid}", headers=cg.headers).json()
    assert seen["active"] and (seen["lat"], seen["lng"]) == (12.97, 77.59)
    # the phone keeps it fresh
    env.client.put("/v1/live/update", headers=a.headers, json={"lat": 13.0, "lng": 77.6, "accuracy": 5})
    seen = env.client.get(f"/v1/live/patient/{pid}", headers=cg.headers).json()
    assert (seen["lat"], seen["lng"]) == (13.0, 77.6)
    assert env.client.get("/v1/live/me", headers=a.headers).json()["active"] is True
    # the public page works with the token only, shows only the first name, and is not indexed
    page = env.client.get("/live/" + link.rsplit("/", 1)[1])
    assert page.status_code == 200 and "Asha is sharing a live location" in page.text
    assert page.headers["cache-control"] == "no-store" and "noindex" in page.headers["x-robots-tag"]
    assert "13.0,77.6" in page.text
    # stop
    assert env.client.post("/v1/live/stop", headers=a.headers).status_code == 204
    assert env.client.get(f"/v1/live/patient/{pid}", headers=cg.headers).json() == {"active": False}
    assert env.client.get("/live/" + link.rsplit("/", 1)[1]).status_code == 404
    assert env.client.put("/v1/live/update", headers=a.headers,
                          json={"lat": 1, "lng": 1}).status_code == 404


def test_only_a_consented_linked_caretaker_can_see_it(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    stranger = env.signup("+919855555555", "caretaker", "Stranger")
    _start(env, a)
    assert env.client.get(f"/v1/live/patient/{pid}", headers=dr.headers).status_code == 403
    assert env.client.get(f"/v1/live/patient/{pid}", headers=stranger.headers).status_code == 404
    assert env.client.get(f"/v1/live/patient/{pid}", headers=a.headers).status_code == 403
    env.consent(a, pid, "caregiver_share", False)
    assert env.client.get(f"/v1/live/patient/{pid}", headers=cg.headers).status_code == 404


def test_validation_and_only_patients_start(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    assert env.client.post("/v1/live/start", headers=cg.headers,
                           json={"lat": 1, "lng": 1}).status_code == 403
    for bad in ({"lat": 95, "lng": 1}, {"lat": 1, "lng": 200}, {"lat": 1, "lng": 1, "minutes": 0},
                {"lat": 1, "lng": 1, "minutes": 999}):
        assert env.client.post("/v1/live/start", headers=a.headers, json=bad).status_code == 422
    assert env.client.get("/live/not-a-real-token-123").status_code == 404


def test_a_new_share_replaces_the_old_link_and_expiry_ends_it(env):
    a, pid = env.make_patient(PHONE_P)
    first = _start(env, a).json()["url"].rsplit("/", 1)[1]
    second = _start(env, a).json()["url"].rsplit("/", 1)[1]
    assert first != second
    assert env.client.get("/live/" + first).status_code == 404
    assert env.client.get("/live/" + second).status_code == 200
    with env.app.state.sessionmaker() as db:
        row = db.get(LiveShare, second)
        row.expires_at = utcnow() - timedelta(minutes=1)
        db.commit()
    assert env.client.get("/live/" + second).status_code == 404
    assert env.client.get("/v1/live/me", headers=a.headers).json() == {"active": False}


def test_it_is_erased_with_the_patient(env):
    a, pid = env.make_patient(PHONE_P)
    _start(env, a)
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    with env.app.state.sessionmaker() as db:
        assert db.query(LiveShare).count() == 0
