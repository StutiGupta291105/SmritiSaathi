"""SMS delivery for OTP codes, behind a small interface so a real provider can
be plugged in without touching the rest of the code.

To add a provider (for example MSG91, Twilio, or AWS SNS in ap-south-1):
implement `send(phone, message)` and return it from `get_provider`. Use a
provider that supports Indian DLT-registered templates for OTP, and never log
the phone number or the message."""
from typing import Protocol

from .config import Settings


class SmsProvider(Protocol):
    def send(self, phone: str, message: str) -> None: ...


class DevSmsProvider:
    """Development and tests only: keeps messages in memory, sends nothing."""

    def __init__(self) -> None:
        self.outbox: list[tuple[str, str]] = []

    def send(self, phone: str, message: str) -> None:
        self.outbox.append((phone, message))


def get_provider(s: Settings) -> SmsProvider:
    if s.sms_provider == "dev":
        return DevSmsProvider()
    raise RuntimeError(f"Unknown SMS provider: {s.sms_provider}")
