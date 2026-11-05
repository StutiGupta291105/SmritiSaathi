"""Doctor opinion chats, the pinned own doctor, and the caregiver-doctor chat."""
PHONE_P, PHONE_C, PHONE_D, PHONE_D2 = "+919876543210", "+919811111111", "+919822222222", "+919833333333"


def _send(env, who, tid, text="hi"):
    return env.client.post(f"/v1/chat/{tid}/messages", headers=who.headers,
                           json={"kind": "text", "text": text})


def _msgs(env, who, tid):
    r = env.client.get(f"/v1/chat/{tid}/messages", headers=who.headers)
    return [m["text"] for m in r.json()] if r.status_code == 200 else r.status_code


def _threads(env, who):
    return env.client.get("/v1/chat/threads", headers=who.headers).json()


def _dir(env, who):
    return env.client.get("/v1/chat/doctors", headers=who.headers).json()


def test_directory_lists_every_doctor_with_the_patients_own_doctor_pinned_first(env):
    a, pid = env.make_patient(PHONE_P)
    own = env.link_member(a, pid, "doctor", PHONE_D)
    other = env.signup(PHONE_D2, "doctor", "Dr Zed")
    rows = _dir(env, a)
    assert [r["doctor_id"] for r in rows][0] == own.user["id"]
    assert rows[0]["pinned"] is True and rows[0]["thread_id"]
    assert {r["doctor_id"] for r in rows} == {own.user["id"], other.user["id"]}
    second = rows[1]
    assert second["pinned"] is False and second["thread_id"] is None
    assert all(set(r) == {"doctor_id", "name", "verified", "pinned", "thread_id"} for r in rows)  # no phone
    # only patients use the directory
    assert env.client.get("/v1/chat/doctors", headers=own.headers).status_code == 403


def test_any_doctor_can_give_an_opinion_but_never_sees_the_patients_data(env):
    a, pid = env.make_patient(PHONE_P)
    other = env.signup(PHONE_D2, "doctor", "Dr Zed")
    r = env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": other.user["id"]})
    assert r.status_code == 200 and r.json()["kind"] == "opinion"
    tid = r.json()["thread_id"]
    again = env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": other.user["id"]})
    assert again.json()["thread_id"] == tid  # reopened, not duplicated
    assert _send(env, a, tid, "Is this tablet safe?").status_code == 201
    assert _send(env, other, tid, "Please ask your own doctor too.").status_code == 201
    assert _msgs(env, a, tid) == _msgs(env, other, tid) == ["Is this tablet safe?", "Please ask your own doctor too."]
    th = _threads(env, other)
    assert [(t["kind"], t["patient_name"], t["unread"]) for t in th] == [("opinion", "Asha", 1)]
    assert th[0]["patient_id"] is None
    # the patient's directory now points at the open conversation
    assert _dir(env, a)[0]["thread_id"] == tid
    # ...but the doctor has no access to anything about the patient
    for path in (f"/v1/patients/{pid}/report?days=7", f"/v1/patients/{pid}/reminders",
                 f"/v1/patients/{pid}/care-reminders"):
        assert env.client.get(path, headers=other.headers).status_code == 404, path
    assert env.client.post(f"/v1/patients/{pid}/care-reminders", headers=other.headers, json={
        "kind": "activity", "label": "x", "hour": 8, "minute": 0}).status_code == 404


def test_an_opinion_chat_is_private_to_its_two_people(env):
    a, pid = env.make_patient(PHONE_P)
    d1 = env.signup(PHONE_D, "doctor", "Dr One")
    d2 = env.signup(PHONE_D2, "doctor", "Dr Two")
    tid = env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": d1.user["id"]}).json()["thread_id"]
    _send(env, a, tid, "private")
    assert _msgs(env, d2, tid) == 404
    assert _send(env, d2, tid).status_code == 404
    stranger, _ = env.make_patient("+919844444444", "Bina")
    assert _msgs(env, stranger, tid) == 404
    assert _threads(env, d2) == []
    assert env.client.post("/v1/chat/opinion", headers=d1.headers, json={"doctor_id": d1.user["id"]}).status_code == 403
    assert env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": "nope"}).status_code == 404
    cg = env.signup(PHONE_C, "caretaker", "Cara")
    assert env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": cg.user["id"]}).status_code == 404


def test_asking_your_own_doctor_opens_the_care_chat_not_an_opinion_chat(env):
    a, pid = env.make_patient(PHONE_P)
    own = env.link_member(a, pid, "doctor", PHONE_D)
    r = env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": own.user["id"]}).json()
    assert r["kind"] == "care"
    assert r["thread_id"] == _dir(env, a)[0]["thread_id"]
    assert _send(env, a, r["thread_id"], "hello doctor").status_code == 201
    assert _msgs(env, own, r["thread_id"]) == ["hello doctor"]


def test_caregiver_and_doctor_are_put_in_touch_once_both_have_accepted(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    assert [t["kind"] for t in _threads(env, cg)] == ["care"]  # no doctor yet: no bridge
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    cg_pro = [t for t in _threads(env, cg) if t["kind"] == "pro"]
    dr_pro = [t for t in _threads(env, dr) if t["kind"] == "pro"]
    assert len(cg_pro) == len(dr_pro) == 1 and cg_pro[0]["link_id"] == dr_pro[0]["link_id"]
    assert cg_pro[0]["peer_role"] == "doctor" and dr_pro[0]["peer_role"] == "caretaker"
    assert cg_pro[0]["patient_name"] == "Asha"
    tid = cg_pro[0]["link_id"]
    assert _send(env, cg, tid, "She skipped lunch today").status_code == 201
    assert _send(env, dr, tid, "Thanks, I will adjust the evening dose").status_code == 201
    assert _msgs(env, cg, tid) == _msgs(env, dr, tid) == ["She skipped lunch today", "Thanks, I will adjust the evening dose"]
    assert [t["unread"] for t in _threads(env, cg) if t["kind"] == "pro"] == [1]
    # calling this twice does not create a second conversation
    assert len([t for t in _threads(env, cg) if t["kind"] == "pro"]) == 1
    # the patient is not part of it, nor is a stranger
    assert _msgs(env, a, tid) == 404 and _send(env, a, tid).status_code == 404
    assert all(t["kind"] != "pro" for t in _threads(env, a))
    stranger = env.signup("+919855555555", "caretaker", "Nosy")
    assert _msgs(env, stranger, tid) == 404


def test_the_caregiver_doctor_chat_closes_when_either_link_or_consent_goes(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    tid = [t for t in _threads(env, cg) if t["kind"] == "pro"][0]["link_id"]
    _send(env, cg, tid, "hello")
    env.consent(a, pid, "doctor_share", False)
    assert _msgs(env, cg, tid) == 404 and _msgs(env, dr, tid) == 404
    assert all(t["kind"] != "pro" for t in _threads(env, cg))
    # withdrawing sharing revokes the link for good, so the chat stays closed even
    # if the patient later consents again: a new invitation is needed
    env.consent(a, pid, "doctor_share", True)
    assert _msgs(env, cg, tid) == 404
    env.consent(a, pid, "caregiver_share", False)
    assert _msgs(env, dr, tid) == 404


def test_a_new_doctor_invitation_restores_the_team_chat_history(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    env.link_member(a, pid, "doctor", PHONE_D)
    tid = [t for t in _threads(env, cg) if t["kind"] == "pro"][0]["link_id"]
    _send(env, cg, tid, "hello")
    env.consent(a, pid, "doctor_share", False)
    dr2 = env.link_member(a, pid, "doctor", PHONE_D2)  # a different doctor takes over
    pro = [t for t in _threads(env, cg) if t["kind"] == "pro"]
    assert len(pro) == 1 and pro[0]["link_id"] != tid  # fresh conversation with the new doctor
    assert _msgs(env, dr2, pro[0]["link_id"]) == []


def test_erasing_the_patient_removes_opinion_and_team_chats(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    dr = env.link_member(a, pid, "doctor", PHONE_D)
    other = env.signup(PHONE_D2, "doctor", "Dr Zed")
    op = env.client.post("/v1/chat/opinion", headers=a.headers, json={"doctor_id": other.user["id"]}).json()["thread_id"]
    _send(env, a, op, "opinion please")
    pro = [t for t in _threads(env, cg) if t["kind"] == "pro"][0]["link_id"]
    _send(env, cg, pro, "team note")
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert {m["body"] for m in exp["messages"]} >= {"opinion please", "team note"}
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    assert _threads(env, other) == [] and _threads(env, cg) == []
    assert _msgs(env, other, op) == 404 and _msgs(env, dr, pro) == 404


def test_a_doctor_only_gets_chats_with_caregivers_of_their_own_patients(env):
    a1, p1 = env.make_patient(PHONE_P, "Asha")
    a2, p2 = env.make_patient("+919844444444", "Bina")
    cg1 = env.link_member(a1, p1, "caretaker", PHONE_C)
    dr1 = env.link_member(a1, p1, "doctor", PHONE_D)
    cg2 = env.link_member(a2, p2, "caretaker", "+919855555555")
    dr2 = env.link_member(a2, p2, "doctor", PHONE_D2)
    for dr, cg, other_cg, name in ((dr1, cg1, cg2, "Asha"), (dr2, cg2, cg1, "Bina")):
        pro = [t for t in _threads(env, dr) if t["kind"] == "pro"]
        assert [(t["peer_name"], t["patient_name"]) for t in pro] == [(cg.user["name"], name)]
        # and no way into the other pair's conversation
        theirs = [t for t in _threads(env, other_cg) if t["kind"] == "pro"][0]["link_id"]
        assert _msgs(env, dr, theirs) == 404
        assert _send(env, dr, theirs).status_code == 404
