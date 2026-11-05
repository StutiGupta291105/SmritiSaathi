"""Caretakers and doctors are invited by ID, and a patient only appears on their
dashboard after they accept."""
import re

CARE_ID = re.compile(r"^(CG|DR)-[A-HJKMNP-Z2-9]{6}$")


def _invite_by_id(env, a, pid, role, care_id, name="Ravi"):
    return env.client.post(f"/v1/patients/{pid}/invites", headers=a.headers, json={
        "role": role, "care_id": care_id, "name": name})


def test_caretakers_and_doctors_get_an_id_and_patients_do_not(env):
    cg = env.signup("+919811111111", "caretaker", "Ravi")
    dr = env.signup("+919822222222", "doctor", "Dr Rao")
    pt = env.signup("+919833333333", "patient", "Asha")
    assert CARE_ID.match(cg.user["care_id"]) and cg.user["care_id"].startswith("CG-")
    assert CARE_ID.match(dr.user["care_id"]) and dr.user["care_id"].startswith("DR-")
    assert pt.user["care_id"] is None
    me = env.client.get("/v1/auth/me", headers=cg.headers).json()
    assert me["care_id"] == cg.user["care_id"]
    again = env.login("+919811111111", "caretaker")
    assert again.user["care_id"] == cg.user["care_id"]  # the ID stays


def test_invite_by_id_shows_only_for_that_person_until_accepted(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    cg = env.signup("+919811111111", "caretaker", "Ravi")
    other = env.signup("+919844444444", "caretaker", "Someone Else")

    # Nothing is shared before an invite: not in the list, not in invitations
    assert env.client.get("/v1/my-patients", headers=cg.headers).json() == []
    assert env.client.get("/v1/invites", headers=cg.headers).json() == []

    r = _invite_by_id(env, a, pid, "caretaker", cg.user["care_id"].lower())  # case-insensitive
    assert r.status_code == 201, r.text
    inv = env.client.get("/v1/invites", headers=cg.headers).json()
    assert len(inv) == 1 and inv[0]["patient_display_name"] == "Asha"
    assert env.client.get("/v1/invites", headers=other.headers).json() == []
    # invited but not accepted: still not on the dashboard, and no report
    assert env.client.get("/v1/my-patients", headers=cg.headers).json() == []
    assert env.client.get(f"/v1/patients/{pid}/report", headers=cg.headers).status_code == 404

    acc = env.client.post(f"/v1/invites/{inv[0]['id']}/accept", headers=cg.headers)
    assert acc.status_code == 200
    mine = env.client.get("/v1/my-patients", headers=cg.headers).json()
    assert [p["patient_id"] for p in mine] == [pid]
    assert env.client.get("/v1/my-patients", headers=other.headers).json() == []


def test_declined_invite_never_shows_the_patient(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    cg = env.signup("+919811111111", "caretaker", "Ravi")
    assert _invite_by_id(env, a, pid, "caretaker", cg.user["care_id"]).status_code == 201
    inv = env.client.get("/v1/invites", headers=cg.headers).json()
    env.client.post(f"/v1/invites/{inv[0]['id']}/decline", headers=cg.headers)
    assert env.client.get("/v1/my-patients", headers=cg.headers).json() == []
    assert env.client.get("/v1/invites", headers=cg.headers).json() == []


def test_bad_ids_are_refused(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    env.consent(a, pid, "doctor_share", True)
    dr = env.signup("+919822222222", "doctor", "Dr Rao")
    assert _invite_by_id(env, a, pid, "caretaker", "hello").status_code == 422
    assert _invite_by_id(env, a, pid, "caretaker", "CG-ABCDEF").status_code == 404  # unknown
    # a doctor's ID cannot be used for a caregiver invite
    assert _invite_by_id(env, a, pid, "caretaker", dr.user["care_id"]).status_code == 422
    assert _invite_by_id(env, a, pid, "doctor", dr.user["care_id"]).status_code == 201
    assert _invite_by_id(env, a, pid, "doctor", dr.user["care_id"]).status_code == 409  # twice


def test_invite_still_needs_the_patients_consent(env):
    a, pid = env.make_patient()
    cg = env.signup("+919811111111", "caretaker", "Ravi")
    r = _invite_by_id(env, a, pid, "caretaker", cg.user["care_id"])
    assert r.status_code == 403


def test_a_dev_database_from_an_older_version_gains_the_new_columns(tmp_path):
    from sqlalchemy import create_engine, inspect, text
    from app.config import Settings
    from app.main import create_app
    url = f"sqlite:///{tmp_path}/old.db"
    eng = create_engine(url)
    with eng.begin() as c:
        c.execute(text("CREATE TABLE users (id VARCHAR(36) PRIMARY KEY, phone_hmac VARCHAR(64), "
                       "phone_last4 VARCHAR(4), role VARCHAR(12), name VARCHAR(120), "
                       "created_at DATETIME, verified_at DATETIME)"))
    create_app(Settings(database_url=url))
    assert "care_id" in {c["name"] for c in inspect(create_engine(url)).get_columns("users")}
