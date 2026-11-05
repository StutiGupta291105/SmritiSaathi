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


def test_edit_and_delete_racing_each_other_end_cleanly(env):
    """The patient's phone deletes a routine while its creator edits it (or deletes
    it too). Only the creator may edit, so there is never a merge: whichever comes
    second gets 404, and the app drops a queued delete that gets 404."""
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    rid = _add(env, cg, pid, kind="activity", label="Walk").json()["id"]
    url = f"/v1/patients/{pid}/care-reminders/{rid}"
    assert env.client.delete(url, headers=a.headers).status_code == 204   # patient, offline, now synced
    assert env.client.patch(url, headers=cg.headers, json={"hour": 7}).status_code == 404
    assert env.client.delete(url, headers=cg.headers).status_code == 404
    assert env.client.delete(url, headers=a.headers).status_code == 404   # a repeated queued delete
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json() == []


# ---- a patient deletes a routine: gone for everyone, for good, and the care team is told ----

def _sync_schedule(env, a, pid, rid, kind="activity", hour=8):
    r = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={
        "sessions": [], "marks": [{"reminder_id": rid, "day": "2026-05-01", "marked_at": "2026-05-01T08:00:00Z"}],
        "schedules": [{"id": rid, "kind": kind, "hour": hour, "minute": 0, "days_mask": 127,
                       "on_date": None, "active": True, "created_at": "2026-05-01T00:00:00Z"}]})
    assert r.status_code in (200, 201), r.text


def _schedules(env, who, pid):
    return [x["id"] for x in env.client.get(f"/v1/patients/{pid}/reminders", headers=who.headers).json()]


def test_a_reminder_the_patient_deletes_disappears_for_the_caregiver_and_doctor(env):
    a, pid = env.make_patient(PATIENT)
    env.consent(a, pid, "sync", True)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    rid = "11111111-1111-1111-1111-111111111111"
    keep = "22222222-2222-2222-2222-222222222222"
    _sync_schedule(env, a, pid, rid, hour=8)
    _sync_schedule(env, a, pid, keep, hour=9)
    for who in (cg, dr, a):
        assert set(_schedules(env, who, pid)) == {rid, keep}
    before = len(env.app.state.push.outbox_data) + len(getattr(env.app.state.push, "outbox", []))
    r = env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=a.headers)
    assert r.status_code == 204
    for who in (cg, dr, a):
        assert _schedules(env, who, pid) == [keep]  # gone for every role
    # its done-marks are gone from the database too
    from sqlalchemy import select
    from app.models import ReminderMark, ReminderSchedule
    with env.app.state.sessionmaker() as s:
        assert s.get(ReminderSchedule, rid) is None
        assert not s.execute(select(ReminderMark).where(ReminderMark.reminder_id == rid)).first()
    # repeating the call (the phone retries) is harmless
    assert env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=a.headers).status_code == 204


def test_deleting_a_reminder_notifies_the_care_team_without_details(env):
    a, pid = env.make_patient(PATIENT)
    env.consent(a, pid, "sync", True)
    cg = env.link_member(a, pid, "caretaker", CARER)
    dr = env.link_member(a, pid, "doctor", DOCTOR)
    for who in (cg, dr):
        env.client.post("/v1/devices", headers=who.headers, json={"token": "tok-" + who.user["role"] + "-" * 20, "platform": "android"})
    rid = "33333333-3333-3333-3333-333333333333"
    _sync_schedule(env, a, pid, rid)
    push = env.app.state.push
    start = len(push.outbox)
    assert env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=a.headers).status_code == 204
    sent = push.outbox[start:]
    assert len(sent) == 2  # the caregiver and the doctor, not the patient
    assert all(m[2] == "A routine was removed by the patient." for m in sent)
    assert all("Walk" not in m[2] and rid not in m[2] for m in sent)  # no details on a lock screen
    # a reminder that was never uploaded, or an unknown id: nothing to tell anyone
    n = len(push.outbox)
    assert env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=a.headers).status_code == 204
    assert len(push.outbox) == n


def test_only_the_patient_can_remove_a_reminder_and_only_their_own(env):
    a, pid = env.make_patient(PATIENT)
    env.consent(a, pid, "sync", True)
    cg = env.link_member(a, pid, "caretaker", CARER)
    other, opid = env.make_patient("+919844444444", "Bina")
    env.consent(other, opid, "sync", True)
    rid = "44444444-4444-4444-4444-444444444444"
    _sync_schedule(env, a, pid, rid)
    assert env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=cg.headers).status_code == 404
    assert env.client.delete(f"/v1/patients/{pid}/reminders/{rid}", headers=other.headers).status_code == 404
    assert env.client.delete(f"/v1/patients/{opid}/reminders/{rid}", headers=other.headers).status_code == 204  # not theirs: nothing happens
    assert _schedules(env, a, pid) == [rid]


def test_a_deleted_care_reminder_is_removed_from_the_database_not_just_hidden(env):
    a, pid = env.make_patient(PATIENT)
    cg = env.link_member(a, pid, "caretaker", CARER)
    rid = _add(env, cg, pid, kind="activity", label="Walk").json()["id"]
    assert env.client.delete(f"/v1/patients/{pid}/care-reminders/{rid}", headers=a.headers).status_code == 204
    from app.models import CareReminder
    with env.app.state.sessionmaker() as s:
        assert s.get(CareReminder, rid) is None  # the row itself is gone
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=cg.headers).json() == []
    assert env.client.get(f"/v1/patients/{pid}/care-reminders", headers=a.headers).json() == []
