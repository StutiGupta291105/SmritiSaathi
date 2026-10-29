"""'Talk to Smriti': a gentle companion for older people, behind a small
provider interface (like SMS) so tests never call the network.

Safety design, in order of importance:
  1. Emergency and distress words are caught here, in code, before any model is
     called. The reply is fixed text pointing to 112 and family. A model is never
     the only thing between a person in trouble and help.
  2. The model is told never to diagnose, give medical or medicine advice, quiz
     memory, or ask for personal details, and to orient gently without
     contradicting. This is a prompt, not a guarantee, so the app also shows a
     visible 'helper program, not a doctor' note.
  3. Nothing the person types or the model says is stored or logged. Only a
     count per day is kept (to limit use).
"""
import re
import unicodedata
from dataclasses import dataclass
from typing import Protocol

from .safety_data import (EMERGENCY_REPLY, EMERGENCY_WORDS, LANGUAGES as LANGUAGE_NAMES,
                          UNAVAILABLE_REPLY)

MAX_TURNS = 12
MAX_CHARS = 600
MAX_REPLY_TOKENS = 1024  # adaptive thinking shares this budget; replies stay short by prompt




_KINDS = {"medicine", "hydration", "activity", "appointment", "birthday", "event"}


class CompanionUnavailable(Exception):
    """The model service could not answer (network, quota, outage)."""


class CompanionProvider(Protocol):
    def reply(self, system: str, messages: list[dict]) -> str: ...


@dataclass
class Turn:
    role: str
    content: str


def _clean(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    text = "".join(ch for ch in text if ch == "\n" or unicodedata.category(ch)[0] != "C")
    return re.sub(r"\s+", " ", text).strip()[:MAX_CHARS]


def clean_turns(raw: list[dict]) -> list[Turn]:
    """Keeps the last MAX_TURNS turns, strictly alternating, ending with the
    person's message. Returns [] if that is not possible."""
    turns = [Turn(t["role"], _clean(t["content"])) for t in raw
             if t.get("role") in ("user", "assistant") and _clean(t.get("content", ""))]
    turns = turns[-MAX_TURNS:]
    while turns and turns[0].role != "user":
        turns.pop(0)
    out: list[Turn] = []
    for t in turns:
        if out and out[-1].role == t.role:
            out[-1] = Turn(t.role, t.content)  # keep the newer of two in a row
        else:
            out.append(t)
    return out if out and out[-1].role == "user" else []


def is_emergency(text: str, lang: str) -> bool:
    low = unicodedata.normalize("NFC", text).lower()
    words = EMERGENCY_WORDS.get(lang, []) + EMERGENCY_WORDS["en"]  # English words in any language
    return any(w in low for w in words)


def build_system(lang: str, first_name: str, now_text: str,
                 today: list[dict]) -> str:
    name = _clean(first_name)[:40] or "friend"
    items = []
    for t in today[:12]:
        kind = t.get("kind")
        if kind in _KINDS:
            hhmm = str(t.get("time", ""))[:5]
            if re.fullmatch(r"\d{2}:\d{2}", hhmm):
                items.append(f"{kind} at {hhmm}{' (done)' if t.get('done') else ''}")
    facts = (f"Their first name: {name}\nCurrent local date and time: {_clean(now_text)[:60]}\n"
             f"Today's reminders: {'; '.join(items) if items else 'none'}")
    return f"""You are Smriti, a warm and patient companion on the phone of an older person who may \
have memory difficulties. Reply in {LANGUAGE_NAMES.get(lang, 'English')}, in simple everyday words.

How to speak:
- Two or three short sentences at most. One idea at a time. Calm, kind, never rushed.
- Plain spoken text only, because it will be read aloud: no lists, no markdown, no emoji.
- Use their first name now and then.

What you do:
- Chat about everyday things, family, food, festivals, songs, the weather, old memories they want to share.
- If they ask the day, date, or time, or what is planned today, answer only from the facts below. Never guess.
- If they seem confused about time, place, or people, orient them gently and never say they are wrong. \
If they speak of someone who has died as if alive, do not correct them; warmly ask about that person and \
gently change the subject.

What you never do:
- Never diagnose, comment on their memory or health, or give medical advice. About medicines, doses, pain or \
symptoms, say you cannot advise and suggest asking their doctor or family, and that the Reminders show their schedule.
- Never quiz them or test their memory.
- Never ask for or accept personal details such as phone numbers, addresses, bank details, passwords, or OTP codes. \
If someone asks them for money or a code, tell them kindly not to share it and to call their family first.
- Never say you are a person. If sincerely asked, say you are a helper program on their phone.
- If they say they are hurt, very unwell, or want to harm themselves, tell them to call 112 and their family now.

Facts you may use:
{facts}"""


class DevCompanion:
    """Tests and local development: a fixed kind reply, nothing leaves the machine."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, list[dict]]] = []

    def reply(self, system: str, messages: list[dict]) -> str:
        self.calls.append((system, messages))
        return "I am here with you. Tell me more."


class AnthropicCompanion:
    def __init__(self, model: str) -> None:
        import anthropic  # imported here so tests and dev need no key
        self._anthropic = anthropic
        self._client = anthropic.Anthropic(max_retries=1, timeout=20.0)
        self._model = model

    def reply(self, system: str, messages: list[dict]) -> str:
        a = self._anthropic
        try:
            r = self._client.messages.create(
                model=self._model, max_tokens=MAX_REPLY_TOKENS, system=system,
                messages=messages, output_config={"effort": "low"})
        except a.APIError as e:  # connection, rate limit, 5xx, auth: all 'unavailable'
            raise CompanionUnavailable(type(e).__name__) from None
        if r.stop_reason == "refusal":
            return ""
        return "".join(b.text for b in r.content if b.type == "text").strip()


def get_provider(provider: str, model: str) -> CompanionProvider:
    if provider == "dev":
        return DevCompanion()
    if provider == "anthropic":
        return AnthropicCompanion(model)
    raise RuntimeError(f"Unknown companion provider: {provider}")
