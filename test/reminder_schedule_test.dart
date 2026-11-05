import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';

Reminder r({int mask = 127, DateTime? on, bool active = true, int h = 9, int m = 0}) =>
    Reminder(
      id: 'x',
      kind: ReminderKind.medicine,
      label: '',
      hour: h,
      minute: m,
      daysMask: mask,
      onDate: on,
      active: active,
    );

void main() {
  test('daily reminder fires later today if time not yet passed', () {
    final from = DateTime(2026, 3, 4, 8, 0); // Wednesday
    expect(nextOccurrences(r(), from), [DateTime(2026, 3, 4, 9, 0)]);
  });

  test('daily reminder moves to tomorrow once time has passed', () {
    final from = DateTime(2026, 3, 4, 9, 0); // exactly at time: strictly after
    expect(nextOccurrences(r(), from), [DateTime(2026, 3, 5, 9, 0)]);
  });

  test('weekday mask is respected (Mon and Fri only)', () {
    const monFri = 1 | 16; // bit0 Monday, bit4 Friday
    final from = DateTime(2026, 3, 4, 10, 0); // Wednesday
    expect(nextOccurrences(r(mask: monFri), from, count: 3), [
      DateTime(2026, 3, 6, 9, 0),
      DateTime(2026, 3, 9, 9, 0),
      DateTime(2026, 3, 13, 9, 0),
    ]);
  });

  test('one-off appointment fires once, never after it has passed', () {
    final on = DateTime(2026, 3, 10);
    expect(nextOccurrences(r(on: on, h: 11, m: 30), DateTime(2026, 3, 4)),
        [DateTime(2026, 3, 10, 11, 30)]);
    expect(nextOccurrences(r(on: on, h: 11, m: 30), DateTime(2026, 3, 11)),
        isEmpty);
  });

  test('inactive or empty-mask reminders never fire', () {
    final from = DateTime(2026, 3, 4);
    expect(nextOccurrences(r(active: false), from), isEmpty);
    expect(nextOccurrences(r(mask: 0), from), isEmpty);
  });

  test('every occurrence gets a heads-up 30 minutes before, unless that is already past', () {
    final now = DateTime(2026, 3, 4, 8, 45); // 09:00 is in 15 min: its heads-up (08:30) is past
    final a = plannedAlerts([r()], now, perReminder: 2);
    expect([for (final x in a) (x.at, x.headsUp)], [
      (DateTime(2026, 3, 4, 9, 0), false),
      (DateTime(2026, 3, 5, 8, 30), true),
      (DateTime(2026, 3, 5, 9, 0), false),
    ]);
    final early = plannedAlerts([r()], DateTime(2026, 3, 4, 7, 0), perReminder: 1);
    expect([for (final x in early) (x.at, x.headsUp)], [
      (DateTime(2026, 3, 4, 8, 30), true),
      (DateTime(2026, 3, 4, 9, 0), false),
    ]);
  });

  test('alerts are limited and ordered, and a dated appointment gets both', () {
    final appt = Reminder(id: 'a', kind: ReminderKind.appointment, label: '', hour: 11, minute: 0,
        onDate: DateTime(2026, 3, 10));
    final a = plannedAlerts([r(), appt], DateTime(2026, 3, 4, 6, 0), limit: 5);
    expect(a.length, 5);
    for (var i = 1; i < a.length; i++) {
      expect(a[i].at.isBefore(a[i - 1].at), isFalse);
    }
    final all = plannedAlerts([appt], DateTime(2026, 3, 4, 6, 0));
    expect([for (final x in all) (x.at, x.headsUp, x.kind)], [
      (DateTime(2026, 3, 10, 10, 30), true, ReminderKind.appointment),
      (DateTime(2026, 3, 10, 11, 0), false, ReminderKind.appointment),
    ]);
  });

  group('repeatingAlerts (the OS repeats them, so no weekly app opening is needed)', () {
    final now = DateTime(2026, 3, 4, 10, 0); // Wednesday

    test('an every-day reminder is one daily alarm plus one daily heads-up', () {
      final a = repeatingAlerts([r()], now);
      expect(a.length, 2);
      expect(a[0].repeat, AlertRepeat.daily);
      expect(a[0].headsUp, isFalse);
      expect(a[0].first, DateTime(2026, 3, 5, 9, 0));
      expect(a[1].headsUp, isTrue);
      expect(a[1].first, DateTime(2026, 3, 5, 8, 30));
    });

    test('a heads-up already past today starts tomorrow, not in the past', () {
      final a = repeatingAlerts([r(h: 10, m: 15)], now); // alarm 10:15, heads-up 09:45
      expect(a.firstWhere((x) => x.headsUp).first, DateTime(2026, 3, 5, 9, 45));
      expect(a.firstWhere((x) => !x.headsUp).first, DateTime(2026, 3, 4, 10, 15));
    });

    test('some weekdays: one weekly alarm per chosen day', () {
      const monFri = 1 | 16;
      final a = repeatingAlerts([r(mask: monFri)], now);
      final main = a.where((x) => !x.headsUp).toList();
      expect(main.map((x) => x.first),
          [DateTime(2026, 3, 6, 9, 0), DateTime(2026, 3, 9, 9, 0)]);
      expect(main.every((x) => x.repeat == AlertRepeat.weekly), isTrue);
    });

    test('a heads-up that crosses midnight lands on the previous weekday', () {
      final a = repeatingAlerts([r(mask: 1, h: 0, m: 10)], now); // Mondays 00:10
      final head = a.firstWhere((x) => x.headsUp);
      expect(head.first, DateTime(2026, 3, 8, 23, 40)); // Sunday night
      expect(head.repeat, AlertRepeat.weekly);
    });

    test('birthday repeats yearly, an appointment is one-off and skips a past heads-up', () {
      final bday = Reminder(
          id: 'b', kind: ReminderKind.birthday, label: '', hour: 9, minute: 0,
          onDate: DateTime(1950, 3, 20));
      final yearly = repeatingAlerts([bday], now);
      expect(yearly.every((x) => x.repeat == AlertRepeat.yearly), isTrue);
      expect(yearly.first.first, DateTime(2026, 3, 20, 9, 0));

      final soon = r(on: DateTime(2026, 3, 4), h: 10, m: 20); // heads-up 09:50 is past
      final one = repeatingAlerts([soon], now);
      expect(one.length, 1);
      expect(one.single.repeat, AlertRepeat.none);
    });

    test('inactive reminders are left out and the limit keeps main alarms first', () {
      expect(repeatingAlerts([r(active: false)], now), isEmpty);
      final many = [for (var i = 0; i < 5; i++) r(h: 6 + i)];
      final a = repeatingAlerts(many, now, limit: 7);
      expect(a.length, 7);
      expect(a.where((x) => !x.headsUp).length, 5);
    });
  });
}
