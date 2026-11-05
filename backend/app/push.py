"""Push delivery behind a small interface, like SMS and the companion.

A push never carries health or usage detail: lock screens are visible to other
people. It only says there is an update and names the person, and the app shows
the details after sign-in.

`FcmPush` (Firebase Cloud Messaging, HTTP v1) is tested here only against a stub
of Google's endpoint, not a live Firebase project; try it on a real device before
relying on it. The Android build adds Firebase only when the repository secret
GOOGLE_SERVICES_JSON exists (see docs/DEPLOYMENT.md)."""
import os
from typing import Protocol

OK, INVALID, FAILED = "ok", "invalid", "failed"


class PushProvider(Protocol):
    def send(self, token: str, title: str, body: str,
             data: dict[str, str] | None = None, silent: bool = False) -> str:
        """Returns OK, INVALID (token is dead: delete it) or FAILED (try later).

        `data` is a small routing hint for the app (e.g. {"type": "chat",
        "link_id": ...}); it never carries health or message content. `silent`
        asks Android to wake the app's background handler instead of showing a
        system notification, so the phone can fetch and schedule a changed
        routine without the patient opening the app (iOS still shows the alert)."""


class DevPush:
    def __init__(self) -> None:
        self.outbox: list[tuple[str, str, str]] = []
        self.outbox_data: list[tuple[dict[str, str] | None, bool]] = []
        self.dead: set[str] = set()

    def send(self, token: str, title: str, body: str,
             data: dict[str, str] | None = None, silent: bool = False) -> str:
        if token in self.dead:
            return INVALID
        self.outbox.append((token, title, body))
        self.outbox_data.append((data, silent))
        return OK


class FcmPush:
    """Credentials come from SMRITI_FCM_CREDENTIALS_JSON (the service-account JSON
    itself, easiest on hosts without files) or SMRITI_FCM_CREDENTIALS_FILE."""

    def __init__(self, project_id: str, credentials_file: str = "",
                 credentials_json: str = "", creds=None) -> None:
        if creds is None:
            from google.oauth2 import service_account  # lazily: dev needs no Google libs
            scopes = ["https://www.googleapis.com/auth/firebase.messaging"]
            if credentials_json:
                import json
                creds = service_account.Credentials.from_service_account_info(
                    json.loads(credentials_json), scopes=scopes)
            else:
                creds = service_account.Credentials.from_service_account_file(
                    credentials_file, scopes=scopes)
        self._creds = creds
        self._url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    def send(self, token: str, title: str, body: str,
             data: dict[str, str] | None = None, silent: bool = False) -> str:
        import requests
        if not self._creds.valid:
            import google.auth.transport.requests as gtr
            self._creds.refresh(gtr.Request())
        try:
            r = requests.post(
                self._url, timeout=10,
                headers={"Authorization": f"Bearer {self._creds.token}"},
                json={"message": self._message(token, title, body, data, silent)})
        except requests.RequestException:
            return FAILED
        if r.status_code == 200:
            return OK
        if r.status_code in (400, 404):  # malformed or unregistered token
            return INVALID
        return FAILED

    @staticmethod
    def _message(token: str, title: str, body: str,
                 data: dict[str, str] | None, silent: bool) -> dict:
        msg: dict = {"token": token, "android": {"priority": "HIGH"}}
        if data:
            msg["data"] = {k: str(v) for k, v in data.items()}  # FCM data values are strings
        if silent and data:
            # Android: data only, so the app's background handler runs (syncs and
            # schedules the alarms, then shows the generic text itself). iOS: the
            # alert is carried by APNs and the app is woken as well.
            msg["apns"] = {"headers": {"apns-priority": "10"},
                           "payload": {"aps": {"alert": {"title": title, "body": body},
                                               "content-available": 1}}}
        else:
            msg["notification"] = {"title": title, "body": body}
        return msg


def get_provider(name: str) -> PushProvider:
    if name == "dev":
        return DevPush()
    if name == "fcm":
        return FcmPush(os.environ["SMRITI_FCM_PROJECT_ID"],
                       os.environ.get("SMRITI_FCM_CREDENTIALS_FILE", ""),
                       os.environ.get("SMRITI_FCM_CREDENTIALS_JSON", ""))
    raise RuntimeError(f"Unknown push provider: {name}")
