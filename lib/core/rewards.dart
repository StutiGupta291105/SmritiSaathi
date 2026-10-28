import 'engagement_alerts.dart';
import 'progress.dart';

/// Rewards for the progress screen: experience points (XP), a star level and
/// achievements. They count how much the person plays, to encourage a daily
/// habit; they are not a measure of ability or health.
class Rewards {
  Rewards({
    required this.xp,
    required this.level,
    required this.levelStartXp,
    required this.nextLevelXp,
    required this.achievements,
  });

  final int xp;

  /// Star level (1, 2, 3 ...), not the game difficulty level.
  final int level;
  final int levelStartXp, nextLevelXp;
  final List<Achievement> achievements;

  /// 0..1 progress through the current star level.
  double get levelProgress =>
      ((xp - levelStartXp) / (nextLevelXp - levelStartXp)).clamp(0.0, 1.0);

  int get unlockedCount => achievements.where((a) => a.unlocked).length;
}

class Achievement {
  const Achievement(this.id, this.unlocked);
  final String id;
  final bool unlocked;
}

const kAchievementIds = [
  'first_game',
  'ten_games',
  'fifty_games',
  'streak3',
  'streak7',
  'all_games',
  'sharp',
];

/// XP needed to reach star [level]: 0, 200, 600, 1200, 2000, ...
int xpForLevel(int level) => 100 * (level - 1) * level;

/// 20 XP for finishing a game plus 5 for every correct answer.
int sessionXp(SessionRecord s) => 20 + 5 * s.correct;

Rewards computeRewards(List<SessionRecord> sessions, {int gameCount = 3}) {
  final xp = sessions.fold<int>(0, (n, s) => n + sessionXp(s));
  var level = 1;
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  final times = sessions.map((s) => s.endedAt).toList();
  final best = bestStreak(times);
  final games = sessions.map((s) => s.game).toSet();
  final unlocked = {
    'first_game': sessions.isNotEmpty,
    'ten_games': sessions.length >= 10,
    'fifty_games': sessions.length >= 50,
    'streak3': best >= 3,
    'streak7': best >= 7,
    'all_games': games.length >= gameCount,
    'sharp': sessions.any((s) => s.trials >= 5 && s.correct == s.trials),
  };
  return Rewards(
    xp: xp,
    level: level,
    levelStartXp: xpForLevel(level),
    nextLevelXp: xpForLevel(level + 1),
    achievements: [
      for (final id in kAchievementIds) Achievement(id, unlocked[id]!)
    ],
  );
}
