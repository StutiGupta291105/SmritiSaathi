/// How a game's difficulty moves from one play to the next.
///
/// A play is "cleared" when most of its rounds were right. The player then
/// stays at the same level for [kClearsToLevelUp] clears (the first clear and
/// the next two), and only after that the game gets a little harder. Two
/// plays in a row that were mostly wrong make it a little easier again. The
/// level never leaves the band the caregiver set (baseline +/- 1).
library;

import 'adaptive_engine.dart';
import 'engagement_alerts.dart' show SessionRecord;

/// Clears needed at one level before the next level is offered.
const int kClearsToLevelUp = 3;

/// Share of right rounds that counts as a clear.
const double kClearAccuracy = 0.6;

/// Plays with fewer rounds than this (left early) count as neither.
const int kMinTrialsForClear = 3;

/// Misses in a row that lower the level.
const int kMissesToLevelDown = 2;

class GameProgress {
  const GameProgress(this.level, this.clears);

  /// Level the next play starts at.
  final int level;

  /// Clears so far at [level] (0 .. kClearsToLevelUp - 1).
  final int clears;
}

bool isClear(SessionRecord s) =>
    s.trials >= kMinTrialsForClear && s.accuracy >= kClearAccuracy;

/// Replays [sessions] of one game (oldest first) and returns where the next
/// play should start.
GameProgress gameProgress(Iterable<SessionRecord> sessions, DifficultyBand band) {
  var level = band.baseline;
  var clears = 0;
  var misses = 0;
  for (final s in sessions) {
    if (s.trials < kMinTrialsForClear) continue; // left early: ignore
    if (isClear(s)) {
      misses = 0;
      clears++;
      if (clears >= kClearsToLevelUp) {
        clears = 0;
        if (level < band.max) level++;
      }
    } else {
      clears = 0;
      misses++;
      if (misses >= kMissesToLevelDown) {
        misses = 0;
        if (level > band.min) level--;
      }
    }
  }
  return GameProgress(band.clamp(level), clears);
}
