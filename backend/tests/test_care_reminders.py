PATIENT, CARER, DOCTOR = "+919876543210", "+919811111111", "+919822222222"


def _body(**kw):
    b = {"kind": "medicine", "label": "Blood pressure tablet", "hour": 9, "minute": 30}
    b.update(kw)
    return b


def _add(env, m, pid, **kw):
    return env.client.post(f"/v1/patients/{pid}/care-reminders", headers=m.headers, json=_body(**kw))


def test_caretaker_and_doctor_add_routines_and_the_patient_sees_them(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    r1 = _add(env, cg, pid, kind="hydration", label="Drink water")
    assert r1.status_code == 201, r1.text
    r2 = _add(env, dr, pid, kind="appointment", label="Clinic visit", hour=11, minute=0,
              days_mask=127, on_date="2026-12-01")
    assert r2.status_code == 201, r2.text
    rows = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json()
    assert [(x["label"], x["created_by_role"], x["mine"]) for x in rows] == [
        ("Drink water", "caretaker", False), ("Clinic visit", "doctor", False)]
    assert rows[1]["on_date"] == "2026-12-01"
    mine = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=cg.headers).json()
    assert [x["mine"] for x in mine] == [True, False]


def test_only_linked_and_consented_members_can_add_or_read(env):
    a, pid = env.make_patient(PATIENT)
    stranger = env.signup("+919844444444", "caretaker", "Nobody")
    assert _add(env, stranger, pid).status_code == 404
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=stranger.headers).status_code == 404
    assert _add(env, a, pid).status_code == 403  # a patient uses their own Reminders
    cg = env.link_member(a, pid, "caretaker", CARER)
    assert _add(env, cg, pid, kind="activity", label="Walk").status_code == 201
    env.consent(a, pid, "caregiver_share", False)  # ends the link
    assert _add(env, cg, pid, kind="activity").status_code == 404
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=cg.headers).status_code == 404


def test_bad_values_are_refused(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    assert _add(env, cg, pid, hour=24).status_code == 422
    assert _add(env, cg, pid, kind="surgery").status_code == 422
    assert _add(env, cg, pid, on_date="01-12-2026").status_code == 422
    assert _add(env, cg, pid, label="x" * 121).status_code == 422


def test_who_may_delete(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    rid = _add(env, cg, pid, kind="activity", label="Walk").json()["id"]
    url = f"/v1/patients/{pid}/care-reminders/{rid}"
    assert env.client.delete(url, headers=dr.headers).status_code == 404  # not theirs
    assert env.client.delete(url, headers=cg.headers).status_code == 204  # the creator
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json() == []
    rid2 = _add(env, dr, pid).json()["id"]
    assert env.client.delete(f"/v1/patients/{pid}/care-reminders/{rid2}", headers=a.headers).status_code == 204
    assert env.client.delete(f"/v1/patients/{pid}/care-reminders/{rid2}", headers=a.headers).status_code == 404


def test_audit_has_no_title_and_erasure_removes_them(env):
    a, pid = env.make_patient(PATIENT)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    _add(env, dr, pid, label="Secret medicine name")
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert [x["label"] for x in exp["care_reminders"]] == ["Secret medicine name"]
    from sqlalchemy import select
    from app.models import AuditEntry
    with env.client.app.state.sessionmaker() as s:
        assert "Secret medicine name" not in str([e.detail for e in s.execute(select(AuditEntry)).scalars()])
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204


def test_only_a_doctor_prescribes_medicine(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    r = _add(env, cg, pid)  # medicine from a caretaker
    assert r.status_code == 403 and "only_doctor_prescribes" in r.text
    ok = _add(env, dr, pid, label="Metformin 500 mg, after food")
    assert ok.status_code == 201
    for kind in ("hydration", "activity", "appointment", "birthday", "event"):
        assert _add(env, cg, pid, kind=kind, label=kind).status_code == 201, kind
    rows = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json()
    meds = [x for x in rows if x["kind"] == "medicine"]
    assert [(m["label"], m["created_by_role"]) for m in meds] == [("Metformin 500 mg, after food", "doctor")]
    # a caretaker cannot remove the doctor's prescription
    url = f"/v1/patients/{pid}/care-reminders/{ok.json()['id']}"
    assert env.client.delete(url, headers=cg.headers).status_code == 404
    assert env.client.delete(url, headers=a.headers).status_code == 204


def test_the_creator_can_edit_and_others_cannot(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    rid = _add(env, dr, pid, label="Metformin 500 mg", hour=9).json()["id"]
    url = f"/v1/patients/{pid}/care-reminders/{rid}"
    ok = env.client.patch(url, headers=dr.headers, json={"label": "Metformin 1000 mg", "hour": 20, "minute": 15})
    assert ok.status_code == 200, ok.text
    got = env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json()
    assert [(x["label"], x["hour"], x["minute"], x["kind"]) for x in got] == [("Metformin 1000 mg", 20, 15, "medicine")]
    assert env.client.patch(url, headers=cg.headers, json={"hour": 1}).status_code == 404   # not theirs
    assert env.client.patch(url, headers=a.headers, json={"hour": 1}).status_code == 403    # patient edits on the phone
    assert env.client.patch(url, headers=dr.headers, json={"hour": 25}).status_code == 422
    assert env.client.patch(url + "x", headers=dr.headers, json={"hour": 1}).status_code == 404


def test_a_caretaker_cannot_edit_a_routine_into_a_prescription_and_dates_can_be_cleared(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    rid = _add(env, cg, pid, kind="appointment", label="Visit", on_date="2026-12-01").json()["id"]
    url = f"/v1/patients/{pid}/care-reminders/{rid}"
    assert env.client.patch(url, headers=cg.headers, json={"kind": "medicine"}).status_code == 403
    ok = env.client.patch(url, headers=cg.headers, json={"kind": "activity", "clear_date": True})
    assert ok.status_code == 200 and ok.json()["on_date"] is None and ok.json()["kind"] == "activity"
    env.consent(a, pid, "caregiver_share", False)
    assert env.client.patch(url, headers=cg.headers, json={"hour": 3}).status_code == 404
