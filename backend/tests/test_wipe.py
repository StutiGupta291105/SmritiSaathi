"""The operator command that clears a test server of its mock data."""
import pytest
from sqlalchemy import func, select

from app import cli
from app.db import Base
from app.models import AuditEntry, Link, Message, Patient, User

PHONE_P, PHONE_C = "+919876543210", "+919811111111"


def _rows(env):
    out = {}
    with env.app.state.sessionmaker() as db:
        for t in Base.metadata.sorted_tables:
            out[t.name] = db.execute(select(func.count()).select_from(t)).scalar_one()
    return out


def test_wipe_deletes_everything_but_keeps_the_tables_and_starts_a_clean_audit_chain(env):
    a, pid = env.make_patient(PHONE_P)
    cg = env.link_member(a, pid, "caretaker", PHONE_C)
    env.client.post("/v1/live/start", headers=a.headers, json={"lat": 1, "lng": 2, "minutes": 5})
    env.client.post("/v1/reports", headers=a.headers, json={"kind": "ai", "excerpt": "x"})
    before = _rows(env)
    assert before["users"] >= 2 and before["patients"] == 1 and before["links"] >= 1
    with env.app.state.sessionmaker() as db:
        assert cli._wipe_all(db, env.settings, "I-UNDERSTAND") == 0
    after = _rows(env)
    assert [n for n, c in after.items() if c and n not in ("audit_log", "audit_head")] == []
    with env.app.state.sessionmaker() as db:
        entries = db.execute(select(AuditEntry)).scalars().all()
        assert [e.action for e in entries] == ["all_data_wiped"]
        from app import audit
        assert audit.verify_chain(db)
    # and the server still works: a new person can sign up
    again = env.signup("+919855555555", "patient", "Real Person")
    assert again.user["name"] == "Real Person"


def test_wipe_needs_the_confirmation_word_and_extra_care_in_production(env, monkeypatch):
    env.make_patient(PHONE_P)
    with env.app.state.sessionmaker() as db:
        assert cli._wipe_all(db, env.settings, "yes") == 2
    assert _rows(env)["patients"] == 1
    from dataclasses import replace
    prod = replace(env.settings, env="prod")
    monkeypatch.delenv("SMRITI_ALLOW_WIPE", raising=False)
    with env.app.state.sessionmaker() as db:
        assert cli._wipe_all(db, prod, "I-UNDERSTAND") == 2
    assert _rows(env)["patients"] == 1
    monkeypatch.setenv("SMRITI_ALLOW_WIPE", "1")
    with env.app.state.sessionmaker() as db:
        assert cli._wipe_all(db, prod, "I-UNDERSTAND") == 0
    assert _rows(env)["patients"] == 0
