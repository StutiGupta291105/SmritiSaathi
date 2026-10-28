import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/progress.dart';

void main() {
  final today = DateTime(2026, 3, 10, 15);

  test('streak counts consecutive days ending today', () {
    final s = [DateTime(2026, 3, 10, 9), DateTime(2026, 3, 9), DateTime(2026, 3, 8)];
    expect(currentStreak(s, today), 3);
  });

  test('streak stays alive if last session was yesterday', () {
    expect(currentStreak([DateTime(2026, 3, 9)], today), 1);
  });

  test('streak resets after a missed day, and is 0 with no sessions', () {
    expect(currentStreak([DateTime(2026, 3, 8)], today), 0);
    expect(currentStreak(const [], today), 0);
  });

  test('last 7 days buckets sessions oldest first', () {
    final s = [DateTime(2026, 3, 10), DateTime(2026, 3, 10), DateTime(2026, 3, 4), DateTime(2026, 3, 3)];
    expect(sessionsLast7Days(s, today), [1, 0, 0, 0, 0, 0, 2]);
  });
}
