from datetime import datetime, timedelta, timezone

from sqlalchemy import select, text

from app import audit
from app.models import AuditEntry
from tests.conftest import Env

DR = "+919822222222"
CARER = "+919811111111"


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat()


def now():
    return datetime.now(timezone.utc)


# ---- patient profile --------------------------------------------------------

def test_patient_profile_rules(env):
    a = env.signup("+919876543210", "patient")
    r = env.client.post("/v1/patients", headers=a.headers,
                        json={"display_name": "Asha", "baseline_level": 3})
    assert r.status_code == 201 and r.json()["tz_offset_minutes"] == 330
    assert env.client.post("/v1/patients", headers=a.headers,
                           json={"display_name": "Again"}).status_code == 409
    assert env.client.get("/v1/patients/me", headers=a.headers).json()["baseline_level"] == 3
    doc = env.signup(DR, "doctor", "Dr")
    assert env.client.post("/v1/patients", headers=doc.headers,
                           json={"display_name": "X"}).status_code == 403


def test_patient_data_is_invisible_to_other_accounts(env):
    a, pid = env.make_patient()
    stranger = env.signup("+919855555555", "patient", "Other")
    env.client.post("/v1/patients", headers=stranger.headers, json={"display_name": "O"})
    for path in (f"/v1/patients/{pid}/report", f"/v1/patients/{pid}/consents",
                 f"/v1/patients/{pid}/links", f"/v1/patients/{pid}/export"):
        assert env.client.get(path, headers=stranger.headers).status_code == 404, path
    assert env.client.delete(f"/v1/patients/{pid}", headers=stranger.headers).status_code == 404


# ---- consent and invites ---------------------------------------------------

def test_invite_needs_matching_consent_and_valid_details(env):
    a, pid = env.make_patient()
    assert env.invite(a, pid, "caretaker", CARER).status_code == 403
    env.consent(a, pid, "caregiver_share", True)
    assert env.invite(a, pid, "caretaker", "12345").status_code == 422
    assert env.invite(a, pid, "caretaker", CARER).status_code == 201
    assert env.invite(a, pid, "caretaker", CARER).status_code == 409
    env.consent(a, pid, "doctor_share", True)
    assert env.invite(a, pid, "doctor", DR).status_code == 422  # needs a registration number
    assert env.invite(a, pid, "doctor", DR, pro_id="MH-1").status_code == 201


def test_invite_reaches_only_the_right_person_and_role(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    env.invite(a, pid, "caretaker", CARER)
    right = env.signup(CARER, "caretaker", "C")
    wrong_number = env.signup("+919833333333", "caretaker", "D")
    wrong_role = env.signup(CARER, "doctor", "Doc")
    assert len(env.client.get("/v1/invites", headers=right.headers).json()) == 1
    assert env.client.get("/v1/invites", headers=wrong_number.headers).json() == []
    assert env.client.get("/v1/invites", headers=wrong_role.headers).json() == []
    inv_id = env.client.get("/v1/invites", headers=right.headers).json()[0]["id"]
    assert env.client.post(f"/v1/invites/{inv_id}/accept",
                           headers=wrong_number.headers).status_code == 404


def test_nothing_is_visible_before_the_invite_is_accepted(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    env.invite(a, pid, "caretaker", CARER)
    m = env.signup(CARER, "caretaker", "C")
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404
    assert env.client.get("/v1/my-patients", headers=m.headers).json() == []


def test_declined_invite_gives_no_access(env):
    a, pid = env.make_patient()
    env.consent(a, pid, "caregiver_share", True)
    env.invite(a, pid, "caretaker", CARER)
    m = env.signup(CARER, "caretaker", "C")
    inv = env.client.get("/v1/invites", headers=m.headers).json()[0]["id"]
    assert env.client.post(f"/v1/invites/{inv}/decline", headers=m.headers).status_code == 200
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404


def test_accepted_member_sees_the_report_and_it_is_audited(env):
    a, pid = env.make_patient()
    m = env.link_member(a, pid, "caretaker", CARER)
    r = env.client.get(f"/v1/patients/{pid}/report", headers=m.headers)
    assert r.status_code == 200 and r.json()["patient"]["display_name"] == "Asha"
    pats = env.client.get("/v1/my-patients", headers=m.headers).json()
    assert [p["patient_id"] for p in pats] == [pid]
    with env.app.state.sessionmaker() as db:
        actions = [e.action for e in db.execute(select(AuditEntry)).scalars()]
    assert "report_viewed" in actions


def test_withdrawing_consent_cuts_access_at_once(env):
    a, pid = env.make_patient()
    m = env.link_member(a, pid, "caretaker", CARER)
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 200
    env.consent(a, pid, "caregiver_share", False)
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404
    assert env.client.get("/v1/my-patients", headers=m.headers).json() == []
    links = env.client.get(f"/v1/patients/{pid}/links", headers=a.headers).json()
    assert links[0]["status"] == "revoked"
    # Granting again does not silently restore the old link.
    env.consent(a, pid, "caregiver_share", True)
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404


def test_caretaker_consent_does_not_open_doctor_access(env):
    a, pid = env.make_patient()
    env.link_member(a, pid, "caretaker", CARER)
    doc = env.signup(DR, "doctor", "Dr")
    assert env.client.get(f"/v1/patients/{pid}/report", headers=doc.headers).status_code == 404


def test_either_side_can_end_a_link_but_strangers_cannot(env):
    a, pid = env.make_patient()
    m = env.link_member(a, pid, "caretaker", CARER)
    link_id = env.client.get(f"/v1/patients/{pid}/links", headers=a.headers).json()[0]["id"]
    stranger = env.signup("+919844444444", "caretaker", "S")
    assert env.client.delete(f"/v1/links/{link_id}", headers=stranger.headers).status_code == 404
    assert env.client.delete(f"/v1/links/{link_id}", headers=m.headers).status_code == 204
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404


def test_caretaker_can_set_baseline_but_doctor_cannot(env):
    a, pid = env.make_patient()
    c = env.link_member(a, pid, "caretaker", CARER)
    d = env.link_member(a, pid, "doctor", DR)
    assert env.client.patch(f"/v1/patients/{pid}/baseline", headers=c.headers,
                            json={"baseline_level": 4}).json()["baseline_level"] == 4
    assert env.client.patch(f"/v1/patients/{pid}/baseline", headers=d.headers,
                            json={"baseline_level": 1}).status_code == 403
    assert env.client.patch(f"/v1/patients/{pid}/baseline", headers=c.headers,
                            json={"baseline_level": 9}).status_code == 422


# ---- sync --------------------------------------------------------------------

def session_payload(i, game="attention", correct=8, minutes_ago=30):
    end = now() - timedelta(minutes=minutes_ago)
    return {"id": f"s-{i}", "game": game, "started_at": iso(end - timedelta(minutes=5)),
            "ended_at": iso(end), "start_level": 2, "end_level": 2,
            "trials": 10, "correct": correct}


def test_sync_needs_the_sync_purpose(env):
    a, pid = env.make_patient(consents=("gameplay", "reminders"))
    r = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                        json={"sessions": [session_payload(1)]})
    assert r.status_code == 403


def test_sync_is_idempotent_and_respects_purposes(env):
    a, pid = env.make_patient(consents=("sync", "gameplay"))  # no 'reminders'
    body = {"sessions": [session_payload(1), session_payload(2)],
            "schedules": [{"id": "r1", "kind": "medicine", "hour": 9, "minute": 0,
                           "created_at": iso(now() - timedelta(days=9))}],
            "marks": [{"reminder_id": "r1", "day": "2026-03-01", "marked_at": iso(now())}]}
    first = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json=body).json()
    assert first == {"sessions": 2, "schedules": 0, "marks": 0}  # reminders not consented
    again = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json=body).json()
    assert again == {"sessions": 0, "schedules": 0, "marks": 0}

    env.consent(a, pid, "reminders", True)
    third = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json=body).json()
    assert third == {"sessions": 0, "schedules": 1, "marks": 1}
    fourth = env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json=body).json()
    assert fourth == {"sessions": 0, "schedules": 1, "marks": 0}  # schedules update in place


def test_sync_rejects_invalid_data(env):
    a, pid = env.make_patient()
    bad = session_payload(1)
    bad["trials"] = 99999
    assert env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                           json={"sessions": [bad]}).status_code == 422
    bad2 = session_payload(2)
    bad2["game"] = "unknown"
    assert env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                           json={"sessions": [bad2]}).status_code == 422


def test_correct_answers_cannot_exceed_trials(env):
    a, pid = env.make_patient()
    s = session_payload(1)
    s["correct"], s["trials"] = 50, 10
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={"sessions": [s]})
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert exp["sessions"][0]["correct"] == 10


def test_nobody_can_sync_into_another_patients_record(env):
    a, pid = env.make_patient()
    b, _ = env.make_patient("+919866666666", "Bina")
    r = env.client.post(f"/v1/patients/{pid}/sync", headers=b.headers,
                        json={"sessions": [session_payload(1)]})
    assert r.status_code == 404
    c = env.link_member(a, pid, "caretaker", CARER)
    assert env.client.post(f"/v1/patients/{pid}/sync", headers=c.headers,
                           json={"sessions": [session_payload(1)]}).status_code == 404


def test_a_session_id_used_by_someone_else_is_ignored_not_overwritten(env):
    a, pid = env.make_patient()
    b, pid_b = env.make_patient("+919866666666", "Bina")
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                    json={"sessions": [session_payload(1, correct=9)]})
    r = env.client.post(f"/v1/patients/{pid_b}/sync", headers=b.headers,
                        json={"sessions": [session_payload(1, correct=1)]})
    assert r.json()["sessions"] == 0
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert exp["sessions"][0]["correct"] == 9


# ---- reports -----------------------------------------------------------------

def test_report_numbers_and_alerts(env):
    a, pid = env.make_patient(consents=("gameplay", "reminders", "sync", "caregiver_share"))
    sessions = [session_payload(i, game="attention" if i % 2 else "routine",
                                correct=9, minutes_ago=60 * 24 * (i // 2) + 30)
                for i in range(6)]
    long_ago = iso(now() - timedelta(days=10))
    body = {"sessions": sessions,
            # A medicine reminder at 00:05 every day, never marked done.
            "schedules": [{"id": "med", "kind": "medicine", "hour": 0, "minute": 5,
                           "created_at": long_ago}]}
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json=body)
    m = env.link_member(a, pid, "caretaker", CARER)
    rep = env.client.get(f"/v1/patients/{pid}/report?days=7", headers=m.headers).json()
    assert rep["games_played"] == 6
    assert {g["game"]: g["sessions"] for g in rep["per_game"]} == {"attention": 3, "routine": 3}
    assert all(abs(g["accuracy"] - 0.9) < 1e-6 for g in rep["per_game"])
    assert len(rep["daily"]) == 7 and sum(rep["daily"]) == 6
    assert rep["adherence"]["expected"] >= 6 and rep["adherence"]["done"] == 0
    kinds = {x["kind"] for x in rep["alerts"]}
    assert "lowAdherence" in kinds
    assert env.client.get(f"/v1/patients/{pid}/report?days=5", headers=m.headers).status_code == 422
    r90 = env.client.get(f"/v1/patients/{pid}/report?days=90", headers=m.headers).json()
    assert len(r90["daily"]) == 13


def test_marks_clear_the_adherence_alert(env):
    a, pid = env.make_patient(consents=("gameplay", "reminders", "sync"))
    today = datetime.now(timezone.utc)
    marks = [{"reminder_id": "med", "day": (today - timedelta(days=i)).date().isoformat(),
              "marked_at": iso(today)} for i in range(-1, 9)]
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={
        "schedules": [{"id": "med", "kind": "medicine", "hour": 0, "minute": 5,
                       "created_at": iso(today - timedelta(days=10))}],
        "marks": marks})
    rep = env.client.get(f"/v1/patients/{pid}/report", headers=a.headers).json()
    kinds = {x["kind"] for x in rep["alerts"]}
    assert "lowAdherence" not in kinds and "medicineNotDone" not in kinds


# ---- export, erase, audit --------------------------------------------------

def test_export_has_the_data_but_no_phone_hashes(env):
    a, pid = env.make_patient()
    env.link_member(a, pid, "caretaker", CARER)
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                    json={"sessions": [session_payload(1)]})
    exp = env.client.get(f"/v1/patients/{pid}/export", headers=a.headers).json()
    assert exp["account"]["phone_last4"] == "3210"
    assert len(exp["sessions"]) == 1 and len(exp["links"]) == 1 and exp["consents"]
    assert "invitee_phone_hmac" not in exp["links"][0]
    assert "9876543210" not in str(exp)


def test_erase_removes_everything_and_the_login(env):
    a, pid = env.make_patient()
    m = env.link_member(a, pid, "caretaker", CARER)
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers,
                    json={"sessions": [session_payload(1)]})
    assert env.client.delete(f"/v1/patients/{pid}", headers=a.headers).status_code == 204
    assert env.client.get("/v1/auth/me", headers=a.headers).status_code == 401
    assert env.client.post("/v1/auth/refresh", json={"refresh_token": a.refresh}).status_code == 401
    assert env.client.get(f"/v1/patients/{pid}/report", headers=m.headers).status_code == 404
    with env.app.state.engine.connect() as conn:
        for table in ("patients", "game_sessions", "consents", "links",
                      "reminder_marks", "reminder_schedules"):
            assert conn.execute(text(f"select count(*) from {table}")).scalar() == 0, table
        left = conn.execute(text("select count(*) from users where role='patient'")).scalar()
        assert left == 0
    with env.app.state.sessionmaker() as db:
        assert audit.verify_chain(db)
        erased = [e for e in db.execute(select(AuditEntry)).scalars()
                  if e.action == "patient_erased"]
    assert len(erased) == 1


def test_audit_chain_detects_edits_and_deletions(env):
    a, pid = env.make_patient()
    env.link_member(a, pid, "caretaker", CARER)
    with env.app.state.sessionmaker() as db:
        assert audit.verify_chain(db)
    with env.app.state.engine.begin() as conn:
        conn.execute(text("update audit_log set detail='edited' where action='invite_created'"))
    with env.app.state.sessionmaker() as db:
        assert not audit.verify_chain(db)

    # Removing a middle entry.
    e2 = Env()
    a2, pid2 = e2.make_patient()
    e2.link_member(a2, pid2, "caretaker", CARER)
    with e2.app.state.engine.begin() as conn:
        conn.execute(text("delete from audit_log where action='invite_created'"))
    with e2.app.state.sessionmaker() as db:
        assert not audit.verify_chain(db)


def test_audit_chain_detects_removal_of_the_newest_entries(env):
    a, pid = env.make_patient()
    env.link_member(a, pid, "caretaker", CARER)
    with env.app.state.sessionmaker() as db:
        assert audit.verify_chain(db)
        assert audit.head_hash(db)
    with env.app.state.engine.begin() as conn:
        conn.execute(text("delete from audit_log where id = (select max(id) from audit_log)"))
    with env.app.state.sessionmaker() as db:
        assert not audit.verify_chain(db)


def test_audit_head_cannot_be_forged_without_the_key(env):
    a, pid = env.make_patient()
    with env.app.state.engine.begin() as conn:
        conn.execute(text("delete from audit_log where id = (select max(id) from audit_log)"))
        row = conn.execute(text("select max(id), hash from audit_log")).one()
        # An attacker rewrites the head to match, but cannot compute the MAC.
        conn.execute(text("update audit_head set last_id=:i, last_hash=:h"),
                     {"i": row[0], "h": row[1]})
    with env.app.state.sessionmaker() as db:
        assert not audit.verify_chain(db)


def test_audit_entries_hold_no_personal_data(env):
    a, pid = env.make_patient(name="Asha Kumari")
    env.link_member(a, pid, "caretaker", CARER)
    with env.app.state.sessionmaker() as db:
        text_dump = " ".join(f"{e.actor} {e.action} {e.detail}"
                             for e in db.execute(select(AuditEntry)).scalars())
    for secret in ("9876543210", "9811111111", "Asha", "Kumari", "Member"):
        assert secret not in text_dump


# ---- snapshot for a new phone --------------------------------------------------

def test_snapshot_returns_history_and_consent_log_for_the_owner_only(env):
    a, pid = env.make_patient()
    m = env.link_member(a, pid, "caretaker", CARER)
    env.client.post(f"/v1/patients/{pid}/sync", headers=a.headers, json={
        "sessions": [session_payload(1), session_payload(2, minutes_ago=10)],
        "schedules": [{"id": "r1", "kind": "medicine", "hour": 9, "minute": 0,
                       "days_mask": 127, "on_date": None, "active": True,
                       "created_at": iso(now())}],
        "marks": [{"reminder_id": "r1", "day": now().date().isoformat(),
                   "marked_at": iso(now())}]})
    snap = env.client.get(f"/v1/patients/{pid}/snapshot", headers=a.headers).json()
    assert snap["patient"]["id"] == pid
    assert [s["id"] for s in snap["sessions"]] == ["s-1", "s-2"]  # oldest first
    assert snap["schedules"][0]["hour"] == 9 and len(snap["marks"]) == 1
    assert snap["consents"] and snap["links"][0]["kind"] == "caretaker"
    assert "9876543210" not in str(snap) and "label" not in str(snap["schedules"])
    # a linked caretaker is not the patient
    assert env.client.get(f"/v1/patients/{pid}/snapshot",
                          headers=m.headers).status_code in (403, 404)


def test_snapshot_is_audited(env):
    a, pid = env.make_patient()
    env.client.get(f"/v1/patients/{pid}/snapshot", headers=a.headers)
    from sqlalchemy import text as _t
    with env.app.state.engine.connect() as conn:
        n = conn.execute(_t("select count(*) from audit_log "
                            "where action='patient_snapshot_read'")).scalar()
    assert n == 1
