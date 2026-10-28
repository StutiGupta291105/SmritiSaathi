import 'adherence.dart';
import 'engagement_alerts.dart';
import 'strings.dart';

/// Report windows offered on the caregiver dashboard.
enum ReportRange { days7, days30, days90 }

int rangeDays(ReportRange r) => switch (r) {
      ReportRange.days7 => 7,
      ReportRange.days30 => 30,
      ReportRange.days90 => 90,
    };

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

List<SessionRecord> sessionsInRange(
    List<SessionRecord> sessions, DateTime now, ReportRange range) {
  final start = DateTime(now.year, now.month, now.day - (rangeDays(range) - 1));
  return sessions.where((s) => !_day(s.endedAt).isBefore(start)).toList();
}

/// Sessions per bar, oldest first: one bar per day for 7 and 30 days, one per
/// week (13 bars) for 3 months.
List<int> sessionBuckets(
    Iterable<DateTime> times, DateTime now, ReportRange range) {
  final days = rangeDays(range);
  final today = _day(now);
  final start = DateTime(today.year, today.month, today.day - (days - 1));
  final perBar = range == ReportRange.days90 ? 7 : 1;
  final bars = (days / perBar).ceil();
  final counts = List<int>.filled(bars, 0);
  for (final t in times) {
    final offset = _day(t).difference(start).inDays;
    if (offset < 0 || offset >= days) continue;
    counts[(offset ~/ perBar).clamp(0, bars - 1)]++;
  }
  return counts;
}

/// Plain-text summary a caregiver can paste into a message to a doctor or
/// family member. It describes use of the app only.
String buildSummary({
  required String lang,
  required String name,
  required ReportRange range,
  required List<SessionRecord> sessionsInRange,
  required AdherenceSummary adherence,
  required List<EngagementAlert> alerts,
  required Map<String, String> gameNames,
}) {
  final lines = <String>[
    '${tr(lang, 'summaryTitle')}: $name',
    trf(lang, 'summaryPeriod', a: rangeDays(range)),
    '${tr(lang, 'gamesPlayed')}: ${sessionsInRange.length}',
  ];
  for (final g in summarizeByGame(sessionsInRange)) {
    lines.add(
        '- ${gameNames[g.game] ?? g.game}: ${trf(lang, 'sessionsCount', a: g.sessions)}, ${(g.accuracy * 100).round()}%');
  }
  lines.add(trf(lang, 'adherenceLine', a: adherence.done, b: adherence.expected));
  lines.add('${tr(lang, 'alertsTitle')}:');
  if (alerts.isEmpty) {
    lines.add('- ${tr(lang, 'noAlerts')}');
  } else {
    for (final a in alerts) {
      lines.add('- ${trf(lang, 'alert_${a.kind.name}', a: a.a, b: a.b)}');
    }
  }
  lines.add(tr(lang, 'summaryNote'));
  return lines.join('\n');
}
