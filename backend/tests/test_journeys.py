"""One walk through the whole product for each kind of user, the way a family would
actually use it: patient, caregiver and doctor together."""
import base64

from tests.test_care import session_payload

P, C, D = "+919876543210", "+919811111111", "+919822222222"


def _invite(env, a, pid, role, member):
    return env.client.post(f"/v1/patients/{pid}/invites", headers=a.headers, json={
        "role": role, "care_id": member.user["care_id"], "name": member.user["name"]})


def _accept(env, member):
    inv = env.client.get("/v1/invites", headers=member.headers).json()
    assert len(inv) == 1
    assert env.client.post(f"/v1/invites/{inv[0]['id']}/accept", headers=member.headers).status_code == 200


def test_full_family_journey(env):
    # --- the patient signs up, consents and plays
    a, pid = env.make_patient(P, "Asha", consents=("gameplay", "reminders", "sync"))
    r = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                        json={"sessions": [session_payload(1), session_payload(2, correct=6)]})
    assert r.json()["sessions"] == 2

    # --- caregiver and doctor sign up, get Care IDs; nothing is visible yet
    cg = env.signup(C, "caretaker", "Ravi")
    dr = env.signup(D, "doctor", "Dr Rao")
    for m in (cg, dr):
        assert env.client.get("/v1/my-patients", headers=m.headers).json() == []

    # --- the patient invites them by Care ID, consenting to each kind of sharing
    env.consent(a, pid, "caregiver_share", True)
    env.consent(a, pid, "doctor_share", True)
    assert _invite(env, a, pid, "caretaker", cg).status_code == 201
    assert _invite(env, a, pid, "doctor", dr).status_code == 201
    _accept(env, cg)
    _accept(env, dr)
    for m in (cg, dr):
        assert [p["patient_id"] for p in env.client.get("/v1/my-patients", headers=m.headers).json()] == [pid]
        rep = env.client.get(f"/v1/patients/{pid}/report?days=30", headers=m.headers)
        assert rep.status_code == 200 and rep.json()["games_played"] == 2, m.user["role"]

    # --- caregiver: sets the baseline, adds routines, cannot prescribe
    assert env.client.patch(f"/v1/patients/{pid}/baseline", headers=cg.headers,
                            json={"baseline_level": 3}).status_code == 200
    add = lambda who, **kw: env.client.post(
        f"/v1/patients/{pid}/care-reminders", headers=who.headers,
        json={"hour": 8, "minute": 0, **kw})
    assert add(cg, kind="hydration", label="Drink water").status_code == 201
    assert add(cg, kind="activity", label="Evening walk", hour=18).status_code == 201
    assert add(cg, kind="medicine", label="Aspirin").status_code == 403

    # --- doctor: cannot set the baseline, prescribes and books an appointment
    assert env.client.patch(f"/v1/patients/{pid}/baseline", headers=dr.headers,
                            json={"baseline_level": 1}).status_code == 403
    assert add(dr, kind="medicine", label="Metformin 500 mg, after food").status_code == 201
    assert add(dr, kind="appointment", label="Clinic visit", on_date="2026-12-01", hour=11).status_code == 201

    # --- the patient's phone receives everything, labelled with who added it
    rows = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json()
    assert sorted((x["label"], x["created_by_role"]) for x in rows) == sorted([
        ("Drink water", "caretaker"), ("Evening walk", "caretaker"),
        ("Metformin 500 mg, after food", "doctor"), ("Clinic visit", "doctor")])

    # --- chat in both directions, with a photo and a voice note
    threads = env.client.get("/v1/chat/threads", headers=a.headers).json()
    assert len(threads) == 2  # separate conversations with each
    link = {t["link_id"] for t in env.client.get("/v1/chat/threads", headers=cg.headers).json()}.pop()
    send = lambda who, **kw: env.client.post(f"/v1/chat/{link}/messages", headers=who.headers,
                                             json={"kind": "text", **kw})
    assert send(a, text="Where are my tablets?").status_code == 201
    assert send(cg, text="In the blue box").status_code == 201
    img = send(a, kind="image", media_b64=base64.b64encode(b"\xff\xd8\xff\xe0" + b"1" * 50).decode(),
               mime="image/jpeg")
    assert img.status_code == 201
    assert send(dr, text="x").status_code in (403, 404)  # not in the caregiver's conversation

    # --- the patient changes their mind: withdrawing doctor sharing ends only the doctor's access
    env.consent(a, pid, "doctor_share", False)
    assert env.client.get(f"/v1/patients/{pid}/report", headers=dr.headers).status_code == 404
    assert add(dr, kind="medicine", label="Another").status_code == 404
    assert env.client.get(f"/v1/patients/{pid}/report", headers=cg.headers).status_code == 200
    left = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json()
    assert any(x["created_by_role"] == "doctor" for x in left)  # prescriptions already on the phone stay

    # --- the patient removes the caregiver; then erases everything
    links = env.client.get(f"/v1/patients/{pid}/links", headers=a.headers)
    assert links.status_code == 200, links.text
    cg_link = [l for l in links.json() if l["member_role"] == "caretaker"]
    assert cg_link, links.json()
    assert env.client.delete(f"/v1/links/{cg_link[0]['id']}", headers=a.headers).status_code == 204
    assert env.client.get(f"/v1/patients/{pid}/report", headers=cg.headers).status_code == 404
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    assert env.client.get("/v1/my-patients", headers=cg.headers).json() == []
