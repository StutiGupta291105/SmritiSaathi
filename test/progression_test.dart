import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adaptive_engine.dart';
import 'package:smriti_assist/core/engagement_alerts.dart';
import 'package:smriti_assist/core/progression.dart';

SessionRecord s(int correct, {int trials = 5}) => SessionRecord(
    game: 'g',
    endedAt: DateTime(2026, 1, 1),
    startLevel: 3,
    endLevel: 3,
    trials: trials,
    correct: correct);

void main() {
  const band = DifficultyBand(3); // 2..4
  test('no history starts at the baseline', () {
    final p = gameProgress([], band);
    expect([p.level, p.clears], [3, 0]);
  });
  test('stays at the same level for three clears, then gets a little harder', () {
    expect(gameProgress([s(5)], band).level, 3);
    expect(gameProgress([s(5), s(4)], band).level, 3);
    final two = gameProgress([s(5), s(4)], band);
    expect(two.clears, 2);
    final three = gameProgress([s(5), s(4), s(3)], band);
    expect([three.level, three.clears], [4, 0]);
  });
  test('never goes above the caregiver band', () {
    final p = gameProgress([for (var i = 0; i < 12; i++) s(5)], band);
    expect(p.level, 4);
  });
  test('a miss restarts the count; two misses make it easier', () {
    expect(gameProgress([s(5), s(5), s(1)], band).clears, 0);
    expect(gameProgress([s(5), s(5), s(1), s(5)], band).level, 3);
    expect(gameProgress([s(1), s(2)], band).level, 2);
    expect(gameProgress([s(1), s(2), s(0), s(0)], band).level, 2); // band floor
  });
  test('plays left early are ignored', () {
    expect(gameProgress([s(0, trials: 1), s(1, trials: 2)], band).level, 3);
  });
}
