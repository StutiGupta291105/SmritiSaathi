import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/engagement_alerts.dart';
import 'package:smriti_assist/core/progress.dart';
import 'package:smriti_assist/core/rewards.dart';

SessionRecord s(DateTime t,
        {String game = 'memory_match', int trials = 10, int correct = 8}) =>
    SessionRecord(
        game: game,
        endedAt: t,
        startLevel: 2,
        endLevel: 2,
        trials: trials,
        correct: correct);

void main() {
  test('no sessions: level 1, 0 XP, nothing unlocked', () {
    final r = computeRewards(const []);
    expect([r.xp, r.level, r.unlockedCount], [0, 1, 0]);
    expect(r.levelProgress, 0);
  });

  test('XP is 20 per game plus 5 per correct answer', () {
    final r = computeRewards([s(DateTime(2026, 3, 1), correct: 8)]);
    expect(r.xp, 60);
  });

  test('star level thresholds are 0, 200, 600, 1200', () {
    expect([for (var l = 1; l <= 4; l++) xpForLevel(l)], [0, 200, 600, 1200]);
    // 5 perfect sessions of 10 = 5 * 70 = 350 XP -> level 2
    final r = computeRewards(
        [for (var d = 1; d <= 5; d++) s(DateTime(2026, 3, d), correct: 10)]);
    expect(r.xp, 350);
    expect(r.level, 2);
    expect(r.levelProgress, closeTo((350 - 200) / (600 - 200), 1e-9));
  });

  test('achievements unlock on their rules', () {
    final sessions = [
      for (var d = 1; d <= 7; d++)
        s(DateTime(2026, 3, d),
            game: ['memory_match', 'attention', 'routine'][d % 3], correct: 10),
    ];
    final r = computeRewards(sessions);
    bool got(String id) => r.achievements.firstWhere((a) => a.id == id).unlocked;
    expect(got('first_game'), isTrue);
    expect(got('streak3'), isTrue);
    expect(got('streak7'), isTrue);
    expect(got('all_games'), isTrue);
    expect(got('sharp'), isTrue);
    expect(got('ten_games'), isFalse);
    expect(got('fifty_games'), isFalse);
  });

  test('a session with few answers is not a perfect session', () {
    final r = computeRewards([s(DateTime(2026, 3, 1), trials: 3, correct: 3)]);
    expect(r.achievements.firstWhere((a) => a.id == 'sharp').unlocked, isFalse);
  });

  test('best streak finds the longest run, not the current one', () {
    final times = [
      DateTime(2026, 3, 1), DateTime(2026, 3, 2), DateTime(2026, 3, 3),
      DateTime(2026, 3, 4), // run of 4
      DateTime(2026, 3, 10), DateTime(2026, 3, 11), // run of 2
      DateTime(2026, 3, 11, 18), // same day counts once
    ];
    expect(bestStreak(times), 4);
    expect(bestStreak(const []), 0);
  });
}
