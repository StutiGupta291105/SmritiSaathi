"""Mirrors the Dart tests for the same rules, so the app and the server agree."""
from datetime import date, datetime, timedelta

from app import analytics as an

NOW = datetime(2026, 3, 20, 12)


def s(days_ago, game="attention", correct=8, end=2, trials=10):
    return an.Sess(game, datetime(2026, 3, 20, 10) - timedelta(days=days_ago), 2, end,
                   trials, correct)


def kinds(alerts):
    return [a.kind for a in alerts]


def test_no_history_no_alerts():
    assert an.compute_alerts([], NOW, 2) == []


def test_regular_play_is_quiet():
    assert an.compute_alerts([s(d) for d in range(10)], NOW, 2) == []


def test_inactive_after_regular_use():
    alerts = an.compute_alerts([s(d) for d in range(4, 12)], NOW, 2)
    a = next(x for x in alerts if x.kind == "inactive")
    assert a.a == 4


def test_new_users_are_not_inactive():
    assert "inactive" not in kinds(an.compute_alerts([s(6), s(5)], NOW, 2))


def test_fewer_sessions():
    sessions = [s(d) for d in range(7, 13)] + [s(1), s(2)]
    a = next(x for x in an.compute_alerts(sessions, NOW, 2) if x.kind == "fewerSessions")
    assert (a.a, a.b) == (2, 6)


def test_accuracy_dip_and_normal_variation():
    dip = [s(d, correct=9) for d in range(9, 3, -1)] + [s(2, correct=5), s(1, correct=5), s(0, correct=5)]
    assert next(x for x in an.compute_alerts(dip, NOW, 2) if x.kind == "accuracyDip").a == 40
    ok = [s(d, correct=8) for d in range(9, 3, -1)] + [s(2, correct=7), s(1, correct=8), s(0, correct=7)]
    assert "accuracyDip" not in kinds(an.compute_alerts(ok, NOW, 2))


def test_baseline_suggestions():
    top = [s(2, end=3), s(1, end=3), s(0, end=3)]
    out = an.compute_alerts(top, NOW, 2)
    assert "suggestRaiseBaseline" in kinds(out) and out[-1].severity == "info"
    bottom = [s(2, end=1), s(1, end=1), s(0, end=1)]
    assert "suggestLowerBaseline" in kinds(an.compute_alerts(bottom, NOW, 2))
    assert an.suggest_baseline(5, [5, 5, 5]) == "none"


def test_attention_alerts_come_before_suggestions():
    sessions = [s(d, end=3) for d in range(11, 3, -1)]
    assert an.compute_alerts(sessions, NOW, 2)[0].severity == "attention"


def rem(id="a", hour=9, kind="medicine", mask=127, on=None, active=True, created=None):
    return an.Rem(id, kind, hour, 0, mask, on, active, created)


def test_due_items_respect_time_created_and_masks():
    now = datetime(2026, 3, 10, 15)  # a Tuesday
    assert len(list(an.due_items([rem(hour=9), rem("b", hour=18)], now, 1))) == 1
    assert len(list(an.due_items([rem()], now, 7))) == 7
    created = datetime(2026, 3, 8, 12)
    days = {d.day for _, d, _ in an.due_items([rem(created=created)], now, 7)}
    assert days == {9, 10}
    assert len(list(an.due_items([rem(mask=2)], now, 7))) == 1  # Tuesday only
    appt = rem("x", kind="appointment", on=date(2026, 3, 9))
    assert len(list(an.due_items([appt], now, 7))) == 1
    assert list(an.due_items([rem(active=False)], now)) == []


def test_adherence_and_overdue():
    now = datetime(2026, 3, 10, 15)
    done = {("a", "2026-03-10"), ("a", "2026-03-09")}
    assert an.adherence([rem()], done, now, 4) == (4, 2)
    morning, noon = rem("m", hour=9), rem("n", hour=14)
    assert an.overdue_medicines([morning, noon], set(), now) == 1  # noon is within the grace period
    assert an.overdue_medicines([morning], {("m", "2026-03-10")}, now) == 0


def test_buckets_and_streak():
    now = datetime(2026, 3, 20, 12)
    b7 = an.buckets([s(0), s(0), s(6)], now, 7)
    assert len(b7) == 7 and (b7[0], b7[-1]) == (1, 2)
    b90 = an.buckets([s(0), s(1), s(8), s(89), s(120)], now, 90)
    assert len(b90) == 13 and b90[-1] == 2 and sum(b90) == 4
    days = {date(2026, 3, 20), date(2026, 3, 19), date(2026, 3, 18)}
    assert an.current_streak(days, date(2026, 3, 20)) == 3
    assert an.current_streak({date(2026, 3, 19)}, date(2026, 3, 20)) == 1
    assert an.current_streak({date(2026, 3, 17)}, date(2026, 3, 20)) == 0
