import base64

from app.models import DeviceToken

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 200
PHONE_P, PHONE_C = "+919876543210", "+919811111111"


def _b64(b):
    return base64.b64encode(b).decode()


def _thread(env, member, role="caretaker"):
    t = env.client.get("/v1/chat/threads", headers=member.headers).json()
    return t[0]["link_id"] if t else None


def _setup(env, role="caretaker"):
    a, pid = env.make_patient(PHONE_P)
    m = env.link_member(a, pid, role, PHONE_C)
    return a, pid, m, _thread(env, a)


def _send(env, auth, link, **body):
    body.setdefault("kind", "text")
    return env.client.post(f"/v1/chat/{link}/messages", headers=auth.headers, json=body)


def test_patient_and_caretaker_exchange_messages_and_history_is_kept(env):
    a, pid, m, link = _setup(env)
    assert _thread(env, m) == link
    assert _send(env, a, link, text="Hello, I need help").status_code == 201
    assert _send(env, m, link, text="On my way").status_code == 201
    for who in (a, m):
        rows = env.client.get(f"/v1/chat/{link}/messages", headers=who.headers).json()
        assert [r["text"] for r in rows] == ["Hello, I need help", "On my way"]
        assert [r["mine"] for r in rows] == ([True, False] if who is a else [False, True])
    # only newer messages when polling
    first = env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).json()[0]["id"]
    news = env.client.get(f"/v1/chat/{link}/messages?after={first}", headers=a.headers).json()
    assert [r["text"] for r in news] == ["On my way"]


def test_unread_counts_and_marking_read(env):
    a, pid, m, link = _setup(env)
    _send(env, a, link, text="one")
    r2 = _send(env, a, link, text="two").json()
    th = env.client.get("/v1/chat/threads", headers=m.headers).json()
    assert th[0]["unread"] == 2 and th[0]["patient_name"] == "Asha"
    assert env.client.get("/v1/chat/threads", headers=a.headers).json()[0]["unread"] == 0
    assert env.client.post(f"/v1/chat/{link}/read", headers=m.headers,
                           json={"upto": r2["id"]}).status_code == 204
    assert env.client.get("/v1/chat/threads", headers=m.headers).json()[0]["unread"] == 0
    rows = env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).json()
    assert all(r["read"] for r in rows)  # the patient can see they were read


def test_photo_and_voice_note_round_trip(env):
    a, pid, m, link = _setup(env)
    img = _send(env, a, link, kind="image", media_b64=_b64(JPEG), mime="image/jpeg", text="my rash")
    assert img.status_code == 201, img.text
    voice = _send(env, m, link, kind="voice", media_b64=_b64(b"AUDIO" * 50), mime="audio/mp4",
                  duration_ms=4200)
    assert voice.status_code == 201, voice.text
    got = env.client.get(f"/v1/chat/media/{img.json()['id']}", headers=m.headers)
    assert got.content == JPEG and got.headers["content-type"] == "image/jpeg"
    v = env.client.get(f"/v1/chat/media/{voice.json()['id']}", headers=a.headers)
    assert v.content == b"AUDIO" * 50
    rows = env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).json()
    assert [(r["kind"], r["has_media"], r["duration_ms"]) for r in rows] == [
        ("image", True, 0), ("voice", True, 4200)]
    assert "media" not in str(rows).replace("has_media", "")  # bytes never in the list


def test_bad_messages_are_refused(env):
    a, pid, m, link = _setup(env)
    assert _send(env, a, link, text="   ").status_code == 422
    assert _send(env, a, link, kind="image", media_b64=_b64(b"not an image"),
                 mime="image/jpeg").status_code == 422
    assert _send(env, a, link, kind="image", media_b64=_b64(JPEG), mime="text/html").status_code == 422
    assert _send(env, a, link, kind="image", media_b64="@@@", mime="image/jpeg").status_code == 422
    big = _b64(b"\xff\xd8\xff" + b"0" * 600_001)
    assert _send(env, a, link, kind="image", media_b64=big, mime="image/jpeg").status_code in (413, 422)


def test_nobody_else_can_read_or_write(env):
    a, pid, m, link = _setup(env)
    _send(env, a, link, text="private")
    stranger = env.signup("+919844444444", "caretaker", "Stranger")
    other_patient = env.signup("+919855555555", "patient", "Other")
    for who in (stranger, other_patient):
        assert env.client.get(f"/v1/chat/{link}/messages", headers=who.headers).status_code == 404
        assert _send(env, who, link, text="hi").status_code == 404
        assert env.client.get("/v1/chat/threads", headers=who.headers).json() == []
    mid = env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).json()[0]["id"]
    assert env.client.get(f"/v1/chat/media/{mid}", headers=stranger.headers).status_code == 404


def test_withdrawing_consent_or_ending_the_link_closes_the_chat(env):
    a, pid, m, link = _setup(env)
    _send(env, a, link, text="hello")
    env.consent(a, pid, "caregiver_share", False)
    assert env.client.get(f"/v1/chat/{link}/messages", headers=m.headers).status_code == 404
    assert env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).status_code == 404
    # withdrawing sharing also ends the link, so asking again does not reopen it
    env.consent(a, pid, "caregiver_share", True)
    assert env.client.get(f"/v1/chat/{link}/messages", headers=m.headers).status_code == 404


def test_ending_the_link_closes_the_chat(env):
    a, pid, m, link = _setup(env)
    assert env.client.get(f"/v1/chat/{link}/messages", headers=m.headers).status_code == 200
    assert env.client.delete(f"/v1/links/{link}", headers=a.headers).status_code == 204
    assert env.client.get(f"/v1/chat/{link}/messages", headers=m.headers).status_code == 404
    assert env.client.get(f"/v1/chat/{link}/messages", headers=a.headers).status_code == 404


def test_doctor_and_caretaker_have_separate_conversations(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", "+919811111111")
    dr = env.link_member(a, pid, "doctor", "+919822222222")
    threads = env.client.get("/v1/chat/threads", headers=a.headers).json()
    assert {t["member_role"] for t in threads} == {"caretaker", "doctor"}
    by_role = {t["member_role"]: t["link_id"] for t in threads}
    _send(env, a, by_role["doctor"], text="for the doctor only")
    assert env.client.get(f"/v1/chat/{by_role['doctor']}/messages", headers=dr.headers).json()
    assert env.client.get(f"/v1/chat/{by_role['doctor']}/messages", headers=cg.headers).status_code == 404


def test_push_says_only_that_there_is_a_message(env):
    a, pid, m, link = _setup(env)
    push = env.client.app.state.push
    r = env.client.post("/v1/devices", headers=m.headers,
                        json={"token": "T" * 30, "platform": "android"})
    assert r.status_code == 204
    _send(env, a, link, text="my secret symptoms")
    assert push.outbox and "secret" not in str(push.outbox)
    assert push.outbox[-1][1:] == ("Smriti Sathi", "You have a new message.")
    # a dead token is dropped, and a failed push never fails the message
    push.dead.add("T" * 30)
    assert _send(env, a, link, text="again").status_code == 201
    r = env.client.post("/v1/devices", headers=m.headers, json={"token": "T" * 30})
    assert r.status_code == 204


def test_contact_phone_is_shared_only_when_chosen_and_only_with_the_patient(env):
    a, pid, m, link = _setup(env)
    th = env.client.get("/v1/chat/threads", headers=a.headers).json()[0]
    assert th["member_phone"] is None
    r = env.client.put("/v1/auth/me/contact", headers=m.headers, json={"phone": "+91 98123 45678"})
    assert r.status_code == 200 and r.json()["contact_phone"] == "+919812345678"
    assert env.client.get("/v1/chat/threads", headers=a.headers).json()[0]["member_phone"] == "+919812345678"
    assert env.client.get("/v1/chat/threads", headers=m.headers).json()[0]["member_phone"] is None
    assert env.client.put("/v1/auth/me/contact", headers=m.headers, json={"phone": "abc"}).status_code == 422
    assert env.client.put("/v1/auth/me/contact", headers=a.headers, json={"phone": "+919812345678"}).status_code == 403
    env.client.put("/v1/auth/me/contact", headers=m.headers, json={"phone": ""})
    assert env.client.get("/v1/chat/threads", headers=a.headers).json()[0]["member_phone"] is None


def test_erasing_the_patient_deletes_the_chat_and_export_lists_it(env):
    a, pid, m, link = _setup(env)
    _send(env, a, link, text="remember me")
    _send(env, a, link, kind="voice", media_b64=_b64(b"AUDIO"), mime="audio/mp4", duration_ms=1000)
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert [x["body"] for x in exp["messages"]] == ["remember me", ""]
    assert all("media" not in x for x in exp["messages"])
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    assert env.client.get("/v1/chat/threads", headers=m.headers).json() == []
