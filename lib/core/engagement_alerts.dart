import 'adaptive_engine.dart';
import 'adherence.dart';

/// One finished game session, as the dashboard and alerts see it.
class SessionRecord {
  const SessionRecord({
    required this.game,
    required this.endedAt,
    required this.startLevel,
    required this.endLevel,
    required this.trials,
    required this.correct,
  });
  final String game;
  final DateTime endedAt; // local time
  final int startLevel, endLevel, trials, correct;

  double get accuracy => trials == 0 ? 0 : correct / trials;
}

enum AlertKind {
  inactive,
  fewerSessions,
  accuracyDip,
  medicineNotDone,
  lowAdherence,
  suggestRaiseBaseline,
  suggestLowerBaseline,
}

/// [attention] alerts are about a change in how the person is using the app;
/// [info] alerts are suggestions. None of them say anything about health: they
/// describe play, and the caregiver decides what, if anything, to do.
enum AlertSeverity { attention, info }

class EngagementAlert {
  const EngagementAlert(this.kind, this.severity, {this.a = 0, this.b = 0});
  final AlertKind kind;
  final AlertSeverity severity;

  /// Numbers used in the message (days, counts, percentage points).
  final int a, b;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Looks at the session history and returns alerts, most important first.
///
/// Rules (kept simple and explainable on purpose):
///  * inactive: at least 5 sessions so far, none for 3 or more days.
///  * fewerSessions: last 7 days have half or fewer sessions than the 7 days
///    before, and that earlier week had at least 4.
///  * accuracyDip: average accuracy over the last 3 sessions is at least 20
///    points below the average of the 5 before them (needs 8 sessions).
///  * medicineNotDone: medicine reminders from today, due 2 or more hours ago,
///    not marked done (worded as "not marked", never "missed").
///  * lowAdherence: fewer than half of the last 7 days' reminders marked done
///    (needs at least 6 that were due).
///  * baseline suggestions come from [suggestBaseline] (3 sessions at the edge
///    of the band).
List<EngagementAlert> computeAlerts({
  required List<SessionRecord> sessions,
  required DateTime now,
  required int baseline,
  int overdueMedicines = 0,
  AdherenceSummary? weekAdherence,
}) {
  final all = [...sessions]..sort((x, y) => x.endedAt.compareTo(y.endedAt));
  final out = <EngagementAlert>[];
  final today = _day(now);

  if (all.length >= 5) {
    final days = today.difference(_day(all.last.endedAt)).inDays;
    if (days >= 3) {
      out.add(EngagementAlert(AlertKind.inactive, AlertSeverity.attention,
          a: days));
    }
  }

  int inWindow(int fromDaysAgo, int toDaysAgo) => all.where((s) {
        final d = today.difference(_day(s.endedAt)).inDays;
        return d >= fromDaysAgo && d <= toDaysAgo;
      }).length;
  final lastWeek = inWindow(0, 6);
  final weekBefore = inWindow(7, 13);
  if (weekBefore >= 4 && lastWeek * 2 <= weekBefore) {
    out.add(EngagementAlert(AlertKind.fewerSessions, AlertSeverity.attention,
        a: lastWeek, b: weekBefore));
  }

  if (all.length >= 8) {
    double mean(Iterable<SessionRecord> r) =>
        r.fold<double>(0, (n, s) => n + s.accuracy) / r.length;
    final recent = all.sublist(all.length - 3);
    final before = all.sublist(all.length - 8, all.length - 3);
    final dip = ((mean(before) - mean(recent)) * 100).round();
    if (dip >= 20) {
      out.add(EngagementAlert(AlertKind.accuracyDip, AlertSeverity.attention,
          a: dip));
    }
  }

  if (overdueMedicines > 0) {
    out.add(EngagementAlert(AlertKind.medicineNotDone, AlertSeverity.attention,
        a: overdueMedicines));
  }
  if (weekAdherence != null &&
      weekAdherence.expected >= 6 &&
      weekAdherence.rate < 0.5) {
    out.add(EngagementAlert(AlertKind.lowAdherence, AlertSeverity.attention,
        a: (weekAdherence.rate * 100).round()));
  }

  final suggestion = suggestBaseline(
    band: DifficultyBand(baseline),
    recentSessionEndLevels: all.map((s) => s.endLevel).toList(),
  );
  if (suggestion == BaselineSuggestion.raise) {
    out.add(const EngagementAlert(
        AlertKind.suggestRaiseBaseline, AlertSeverity.info));
  } else if (suggestion == BaselineSuggestion.lower) {
    out.add(const EngagementAlert(
        AlertKind.suggestLowerBaseline, AlertSeverity.info));
  }

  out.sort((x, y) => x.severity.index.compareTo(y.severity.index));
  return out;
}

/// Games played and average accuracy for one game.
class GameSummary {
  const GameSummary(this.game, this.sessions, this.accuracy);
  final String game;
  final int sessions;
  final double accuracy; // 0..1
}

List<GameSummary> summarizeByGame(List<SessionRecord> sessions) {
  final by = <String, List<SessionRecord>>{};
  for (final s in sessions) {
    by.putIfAbsent(s.game, () => []).add(s);
  }
  return [
    for (final e in by.entries)
      GameSummary(
          e.key,
          e.value.length,
          e.value.fold<double>(0, (n, s) => n + s.accuracy) / e.value.length)
  ]..sort((a, b) => a.game.compareTo(b.game));
}
