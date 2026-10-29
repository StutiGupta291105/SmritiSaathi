"""Push delivery behind a small interface, like SMS and the companion.

A push never carries health or usage detail: lock screens are visible to other
people. It only says there is an update and names the person, and the app shows
the details after sign-in.

`FcmPush` (Firebase Cloud Messaging, HTTP v1) is written from the documented API
but has NOT been run against a live Firebase project; test it with a real device
before relying on it. The Android app also needs the Firebase plugin and a
`google-services.json`, which are not part of the build yet."""
import os
from typing import Protocol

OK, INVALID, FAILED = "ok", "invalid", "failed"


class PushProvider(Protocol):
    def send(self, token: str, title: str, body: str) -> str:
        """Returns OK, INVALID (token is dead: delete it) or FAILED (try later)."""


class DevPush:
    def __init__(self) -> None:
        self.outbox: list[tuple[str, str, str]] = []
        self.dead: set[str] = set()

    def send(self, token: str, title: str, body: str) -> str:
        if token in self.dead:
            return INVALID
        self.outbox.append((token, title, body))
        return OK


class FcmPush:
    def __init__(self, project_id: str, credentials_file: str) -> None:
        from google.oauth2 import service_account  # imported lazily: dev needs no Google libs
        self._creds = service_account.Credentials.from_service_account_file(
            credentials_file, scopes=["https://www.googleapis.com/auth/firebase.messaging"])
        self._url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    def send(self, token: str, title: str, body: str) -> str:
        import google.auth.transport.requests as gtr
        import requests
        if not self._creds.valid:
            self._creds.refresh(gtr.Request())
        try:
            r = requests.post(
                self._url, timeout=10,
                headers={"Authorization": f"Bearer {self._creds.token}"},
                json={"message": {"token": token,
                                  "notification": {"title": title, "body": body},
                                  "android": {"priority": "HIGH"}}})
        except requests.RequestException:
            return FAILED
        if r.status_code == 200:
            return OK
        if r.status_code in (400, 404):  # malformed or unregistered token
            return INVALID
        return FAILED


def get_provider(name: str) -> PushProvider:
    if name == "dev":
        return DevPush()
    if name == "fcm":
        return FcmPush(os.environ["SMRITI_FCM_PROJECT_ID"],
                       os.environ["SMRITI_FCM_CREDENTIALS_FILE"])
    raise RuntimeError(f"Unknown push provider: {name}")
