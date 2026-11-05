"""Care notes: a shared log for the caregiver and doctor of one patient."""
PHONE_P, PHONE_C, PHONE_D, PHONE_D2 = "+919876543210", "+919811111111", "+919822222222", "+919833333333"


def _url(pid, nid=""):
    return f"/v1/patients/{pid}/care-notes" + (f"/{nid}" if nid else "")


def test_caregiver_and_doctor_share_notes_the_patient_does_not_get_them(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    r = env.client.post(_url(pid), headers=cg.headers, json={"body": "  Skipped lunch today  "})
    assert r.status_code == 201 and r.json()["body"] == "Skipped lunch today" and r.json()["mine"] is True
    env.client.post(_url(pid), headers=dr.headers, json={"body": "Reduce evening dose"})
    for who in (cg, dr):
        rows = env.client.get(_url(pid), headers=who.headers).json()
        assert [n["body"] for n in rows] == ["Reduce evening dose", "Skipped lunch today"]  # newest first
        assert [n["mine"] for n in rows] == ([False, True] if who is cg else [True, False])
        assert {n["author_role"] for n in rows} == {"caretaker", "doctor"}
    assert env.client.get(_url(pid), headers=a.headers).status_code == 403  # patient app: not for patients


def test_only_the_author_deletes_and_validation(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    nid = env.client.post(_url(pid), headers=cg.headers, json={"body": "mine"}).json()["id"]
    assert env.client.delete(_url(pid, nid), headers=dr.headers).status_code == 404
    assert env.client.post(_url(pid), headers=cg.headers, json={"body": "   "}).status_code == 422
    assert env.client.post(_url(pid), headers=cg.headers, json={"body": "x" * 501}).status_code == 422
    assert env.client.delete(_url(pid, nid), headers=cg.headers).status_code == 204
    assert env.client.delete(_url(pid, nid), headers=cg.headers).status_code == 404
    assert env.client.get(_url(pid), headers=dr.headers).json() == []


def test_notes_follow_the_link_and_consent_and_are_private_to_the_care_team(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    stranger = env.signup("+919855555555", "doctor", "Dr Other")
    other_pat, other_pid = env.make_patient("+919844444444", "Bina")
    env.client.post(_url(pid), headers=cg.headers, json={"body": "private"})
    assert env.client.get(_url(pid), headers=stranger.headers).status_code == 404
    assert env.client.post(_url(pid), headers=stranger.headers, json={"body": "x"}).status_code == 404
    assert env.client.get(_url(pid), headers=other_pat.headers).status_code == 403
    env.consent(a, pid, "caregiver_share", False)  # also revokes the link
    assert env.client.get(_url(pid), headers=cg.headers).status_code == 404


def test_notes_are_exported_and_erased_with_the_patient(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    env.client.post(_url(pid), headers=cg.headers, json={"body": "note for export"})
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert [n["body"] for n in exp["care_notes"]] == ["note for export"]
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    from sqlalchemy import select
    from app.models import CareNote
    with env.app.state.sessionmaker() as s:
        assert s.execute(select(CareNote)).first() is None
