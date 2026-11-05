/// Rule-based adaptive difficulty (staircase method).
///
/// Design rules (see README):
///  * The CAREGIVER sets the baseline level. The engine never leaves a band of
///    +/-1 around it, so difficulty cannot drift without a human decision.
///  * The engine only adapts within a session; across sessions it can SUGGEST a
///    baseline change to the caregiver, never apply one.
///  * Nothing here is a clinical measure. It tracks engagement/performance only.
library;

import 'dart:convert';

const int kMinLevel = 1;
const int kMaxLevel = 5;

class DifficultyBand {
  const DifficultyBand(this.baseline)
      : assert(baseline >= kMinLevel && baseline <= kMaxLevel);

  final int baseline;

  int get min => (baseline - 1).clamp(kMinLevel, kMaxLevel);
  int get max => (baseline + 1).clamp(kMinLevel, kMaxLevel);

  int clamp(int level) => level.clamp(min, max);
}

enum LevelChange { none, up, down }

class AdaptiveEngine {
  AdaptiveEngine({
    required this.band,
    int? startLevel,
    this.upAfter = 3,
    this.downAfter = 2,
    this.slowResponseMs = 8000,
  }) : level = band.clamp(startLevel ?? band.baseline);

  final DifficultyBand band;

  /// Consecutive good trials needed to step up.
  final int upAfter;

  /// Consecutive misses needed to step down.
  final int downAfter;

  /// A correct answer slower than this does not count toward stepping up
  /// (but is not penalised either).
  final int slowResponseMs;

  int level;
  int _goodStreak = 0;
  int _missStreak = 0;

  int trials = 0;
  int correctTrials = 0;

  /// Per-level tally of this session: level -> [trials, correct]. Stored with
  /// the session so the ability model can learn from it later.
  final Map<int, List<int>> levelStats = {};

  String levelStatsJson() =>
      jsonEncode({for (final e in levelStats.entries) '${e.key}': e.value});

  double get accuracy => trials == 0 ? 0 : correctTrials / trials;

  LevelChange recordTrial({required bool correct, required int responseMs}) {
    final tally = levelStats.putIfAbsent(level, () => [0, 0]);
    tally[0]++;
    if (correct) tally[1]++;
    trials++;
    if (correct) {
      correctTrials++;
      _missStreak = 0;
      if (responseMs <= slowResponseMs) {
        _goodStreak++;
      }
      if (_goodStreak >= upAfter) {
        _goodStreak = 0;
        if (level < band.max) {
          level++;
          return LevelChange.up;
        }
      }
    } else {
      _goodStreak = 0;
      _missStreak++;
      if (_missStreak >= downAfter) {
        _missStreak = 0;
        if (level > band.min) {
          level--;
          return LevelChange.down;
        }
      }
    }
    return LevelChange.none;
  }
}

enum BaselineSuggestion { none, raise, lower }

/// Looks at where the last [window] sessions ended. If they all sat at the top
/// (or bottom) of the band and the baseline can still move that way, suggest it
/// to the caregiver. This is only a suggestion.
BaselineSuggestion suggestBaseline({
  required DifficultyBand band,
  required List<int> recentSessionEndLevels,
  int window = 3,
}) {
  if (recentSessionEndLevels.length < window) return BaselineSuggestion.none;
  final recent =
      recentSessionEndLevels.sublist(recentSessionEndLevels.length - window);
  if (band.max > band.baseline && recent.every((l) => l >= band.max)) {
    return BaselineSuggestion.raise;
  }
  if (band.min < band.baseline && recent.every((l) => l <= band.min)) {
    return BaselineSuggestion.lower;
  }
  return BaselineSuggestion.none;
}
