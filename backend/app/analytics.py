"""Reports and alerts, computed on the server so a caregiver or doctor sees the
same numbers the patient's own app shows. These mirror the rules in the Dart
app (lib/core/engagement_alerts.dart, adherence.dart, reporting.dart). All
datetimes here are the patient's LOCAL wall-clock time (naive).

Alerts describe how the app is used, never health."""
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

KINDS_ATTENTION = {"inactive", "fewerSessions", "accuracyDip",
                   "medicineNotDone", "lowAdherence"}


@dataclass
class Sess:
    game: str
    ended_at: datetime  # local
    start_level: int
    end_level: int
    trials: int
    correct: int

    @property
    def accuracy(self) -> float:
        return 0.0 if self.trials == 0 else self.correct / self.trials


@dataclass
class Rem:
    id: str
    kind: str
    hour: int
    minute: int
    days_mask: int
    on_date: date | None
    active: bool
    created_at: datetime | None  # local


@dataclass
class Alert:
    kind: str
    severity: str  # 'attention' | 'info'
    a: int = 0
    b: int = 0


# ---- reminders: what was due, what was marked done --------------------------

def occurs_on(r: Rem, day: date) -> bool:
    if not r.active:
        return False
    if r.on_date is not None:
        return r.on_date == day
    return (r.days_mask >> (day.isoweekday() - 1)) & 1 == 1


def due_items(rems: list[Rem], now: datetime, days: int = 7):
    today = now.date()
    for r in rems:
        for i in range(days):
            day = today - timedelta(days=i)
            if not occurs_on(r, day):
                continue
            at = datetime.combine(day, time(r.hour, r.minute))
            if at > now:
                continue
            if r.created_at is not None and at < r.created_at:
                continue
            yield r, day, at


def adherence(rems, done: set[tuple[str, str]], now: datetime, days: int = 7):
    due = list(due_items(rems, now, days))
    got = sum(1 for r, day, _ in due if (r.id, day.isoformat()) in done)
    return len(due), got


def overdue_medicines(rems, done, now, grace=timedelta(hours=2)) -> int:
    return sum(
        1 for r, day, at in due_items(rems, now, 1)
        if r.kind == "medicine" and at + grace <= now
        and (r.id, day.isoformat()) not in done
    )


# ---- reports -----------------------------------------------------------------

def current_streak(days: set[date], today: date) -> int:
    d = today if today in days else today - timedelta(days=1)
    n = 0
    while d in days:
        n += 1
        d -= timedelta(days=1)
    return n


def sessions_in_range(sessions: list[Sess], now: datetime, range_days: int) -> list[Sess]:
    start = now.date() - timedelta(days=range_days - 1)
    return [s for s in sessions if s.ended_at.date() >= start]


def buckets(sessions: list[Sess], now: datetime, range_days: int) -> list[int]:
    """One bar per day for 7 and 30 days, one per week (13 bars) for 90."""
    start = now.date() - timedelta(days=range_days - 1)
    per_bar = 7 if range_days == 90 else 1
    bars = -(-range_days // per_bar)
    out = [0] * bars
    for s in sessions:
        offset = (s.ended_at.date() - start).days
        if 0 <= offset < range_days:
            out[min(offset // per_bar, bars - 1)] += 1
    return out


def per_game(sessions: list[Sess]) -> list[dict]:
    by: dict[str, list[Sess]] = {}
    for s in sessions:
        by.setdefault(s.game, []).append(s)
    return [
        {"game": g, "sessions": len(v),
         "accuracy": round(sum(x.accuracy for x in v) / len(v), 4)}
        for g, v in sorted(by.items())
    ]


# ---- alerts ------------------------------------------------------------------

def suggest_baseline(baseline: int, end_levels: list[int], window: int = 3) -> str:
    lo, hi = max(1, baseline - 1), min(5, baseline + 1)
    if len(end_levels) < window:
        return "none"
    recent = end_levels[-window:]
    if hi > baseline and all(l >= hi for l in recent):
        return "raise"
    if lo < baseline and all(l <= lo for l in recent):
        return "lower"
    return "none"


def compute_alerts(sessions: list[Sess], now: datetime, baseline: int,
                   overdue: int = 0, week: tuple[int, int] | None = None) -> list[Alert]:
    allv = sorted(sessions, key=lambda s: s.ended_at)
    out: list[Alert] = []
    today = now.date()

    if len(allv) >= 5:
        days = (today - allv[-1].ended_at.date()).days
        if days >= 3:
            out.append(Alert("inactive", "attention", days))

    def in_window(frm: int, to: int) -> int:
        return sum(1 for s in allv if frm <= (today - s.ended_at.date()).days <= to)

    last_week, week_before = in_window(0, 6), in_window(7, 13)
    if week_before >= 4 and last_week * 2 <= week_before:
        out.append(Alert("fewerSessions", "attention", last_week, week_before))

    if len(allv) >= 8:
        def mean(v): return sum(s.accuracy for s in v) / len(v)
        dip = round((mean(allv[-8:-3]) - mean(allv[-3:])) * 100)
        if dip >= 20:
            out.append(Alert("accuracyDip", "attention", dip))

    if overdue > 0:
        out.append(Alert("medicineNotDone", "attention", overdue))
    if week is not None and week[0] >= 6 and week[1] / week[0] < 0.5:
        out.append(Alert("lowAdherence", "attention", round(week[1] / week[0] * 100)))

    sug = suggest_baseline(baseline, [s.end_level for s in allv])
    if sug == "raise":
        out.append(Alert("suggestRaiseBaseline", "info"))
    elif sug == "lower":
        out.append(Alert("suggestLowerBaseline", "info"))

    out.sort(key=lambda a: 0 if a.severity == "attention" else 1)
    return out
