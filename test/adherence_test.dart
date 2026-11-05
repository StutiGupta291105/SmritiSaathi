import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adherence.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';

Reminder r(String id,
        {ReminderKind kind = ReminderKind.medicine,
        int hour = 9,
        int mask = 127,
        DateTime? on,
        bool active = true,
        DateTime? created}) =>
    Reminder(
        id: id,
        kind: kind,
        label: '',
        hour: hour,
        minute: 0,
        daysMask: mask,
        onDate: on,
        active: active,
        createdAt: created);

final now = DateTime(2026, 3, 10, 15); // Tuesday, 3 pm

void main() {
  test('only occurrences whose time has passed are counted', () {
    final due = dueItems([r('a', hour: 9), r('b', hour: 18)], now, days: 1);
    expect(due.map((d) => d.reminder.id), ['a']); // 18:00 has not happened yet
  });

  test('a daily reminder counts once per day over the window', () {
    expect(dueItems([r('a')], now, days: 7).length, 7);
  });

  test('days before the reminder was created are not counted', () {
    final created = DateTime(2026, 3, 8, 12);
    final due = dueItems([r('a', created: created)], now, days: 7);
    // 8th 09:00 is before creation (12:00); 9th and 10th count.
    expect(due.map((d) => d.day.day).toSet(), {9, 10});
  });

  test('weekday masks and one-off dates are respected', () {
    const tuesdayOnly = 2; // bit 1 = Tuesday
    expect(dueItems([r('a', mask: tuesdayOnly)], now, days: 7).length, 1);
    final appt = r('x', kind: ReminderKind.appointment, on: DateTime(2026, 3, 9));
    expect(dueItems([appt], now, days: 7).length, 1);
  });

  test('inactive reminders are not counted', () {
    expect(dueItems([r('a', active: false)], now), isEmpty);
  });

  test('adherence counts done marks against what was due', () {
    final reminders = [r('a')];
    final done = {
      doneKey('a', DateTime(2026, 3, 10)),
      doneKey('a', DateTime(2026, 3, 9)),
    };
    final s = adherence(reminders, done, now, days: 4);
    expect([s.expected, s.done], [4, 2]);
    expect(s.rate, 0.5);
    expect(adherence(const [], {}, now).rate, 1);
  });

  test('overdue medicines need the grace period to pass and no done mark', () {
    final morning = r('m', hour: 9); // due 09:00, grace 2h -> overdue by 11:00
    final noon = r('n', hour: 14); // only 1 hour ago: within grace
    final water = r('w', kind: ReminderKind.hydration, hour: 8);
    expect(
        overdueMedicines([morning, noon, water], {}, now)
            .map((d) => d.reminder.id),
        ['m']);
    expect(
        overdueMedicines([morning], {doneKey('m', DateTime(2026, 3, 10))}, now),
        isEmpty);
  });
}
