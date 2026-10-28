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
}
