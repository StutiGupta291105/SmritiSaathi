import re
from dataclasses import dataclass

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.sms import DevSmsProvider


@dataclass
class Auth:
    headers: dict
    user: dict
    refresh: str
    access: str


class Env:
    def __init__(self, **over):
        self.sms = DevSmsProvider()
        base = dict(database_url="sqlite://", requests_per_minute_ip=100_000,
                    otp_requests_per_hour_ip=1000)
        base.update(over)
        self.settings = Settings(**base)
        self.app = create_app(self.settings, self.sms)
        self.client = TestClient(self.app)

    def last_code(self) -> str:
        return re.match(r"(\d{6})", self.sms.outbox[-1][1]).group(1)

    def request_otp(self, phone, role):
        return self.client.post("/v1/auth/otp/request", json={"phone": phone, "role": role})

    def verify(self, challenge_id, code, mode="login", name=None):
        body = {"challenge_id": challenge_id, "code": code, "mode": mode}
        if name:
            body["name"] = name
        return self.client.post("/v1/auth/otp/verify", json=body)

    def signup(self, phone="+919876543210", role="patient", name="Asha") -> Auth:
        ch = self.request_otp(phone, role).json()["challenge_id"]
        r = self.verify(ch, self.last_code(), "signup", name)
        assert r.status_code == 200, r.text
        return self._auth(r.json())

    def login(self, phone, role) -> Auth:
        ch = self.request_otp(phone, role).json()["challenge_id"]
        r = self.verify(ch, self.last_code(), "login")
        assert r.status_code == 200, r.text
        return self._auth(r.json())

    @staticmethod
    def _auth(j) -> Auth:
        return Auth({"Authorization": f"Bearer {j['access_token']}"}, j["user"],
                    j["refresh_token"], j["access_token"])

    # -- helpers for patients and consents
    def make_patient(self, phone="+919876543210", name="Asha",
                     consents=("gameplay", "reminders", "sync")):
        a = self.signup(phone, "patient", name)
        r = self.client.post("/v1/patients", headers=a.headers,
                             json={"display_name": name, "baseline_level": 2})
        assert r.status_code == 201, r.text
        pid = r.json()["id"]
        for c in consents:
            self.consent(a, pid, c, True)
        return a, pid

    def consent(self, auth, pid, purpose, granted):
        r = self.client.post(f"/v1/patients/{pid}/consents", headers=auth.headers, json={
            "consents": [{"purpose": purpose, "granted": granted, "given_by_name": "Asha",
                          "given_by_relation": "self", "notice_version": "v2"}]})
        assert r.status_code == 201, r.text
        return r.json()

    def invite(self, auth, pid, role, phone, name="Member", pro_id=""):
        return self.client.post(f"/v1/patients/{pid}/invites", headers=auth.headers, json={
            "role": role, "phone": phone, "name": name, "professional_id": pro_id})

    def link_member(self, patient_auth, pid, role="caretaker", phone="+919811111111"):
        """Patient invites, member signs up and accepts. Returns the member's auth."""
        purpose = "caregiver_share" if role == "caretaker" else "doctor_share"
        self.consent(patient_auth, pid, purpose, True)
        r = self.invite(patient_auth, pid, role, phone, pro_id="REG1" if role == "doctor" else "")
        assert r.status_code == 201, r.text
        m = self.signup(phone, role, "Member")
        inv = self.client.get("/v1/invites", headers=m.headers).json()
        assert len(inv) == 1
        acc = self.client.post(f"/v1/invites/{inv[0]['id']}/accept", headers=m.headers)
        assert acc.status_code == 200, acc.text
        return m


@pytest.fixture
def env():
    return Env()
