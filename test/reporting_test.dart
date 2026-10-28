import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adherence.dart';
import 'package:smriti_assist/core/engagement_alerts.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/core/reporting.dart';

final now = DateTime(2026, 3, 20, 12);
DateTime ago(int d) => DateTime(2026, 3, 20 - d, 10);

SessionRecord s(DateTime t, {String game = 'attention', int correct = 8}) =>
    SessionRecord(
        game: game,
        endedAt: t,
        startLevel: 2,
        endLevel: 2,
        trials: 10,
        correct: correct);

void main() {
  test('range filter keeps only sessions inside the window', () {
    final all = [s(ago(0)), s(ago(6)), s(ago(7)), s(ago(40))];
    expect(sessionsInRange(all, now, ReportRange.days7).length, 2);
    expect(sessionsInRange(all, now, ReportRange.days30).length, 3);
    expect(sessionsInRange(all, now, ReportRange.days90).length, 4);
  });

  test('7 and 30 day charts have one bar per day, oldest first', () {
    final b7 = sessionBuckets([ago(0), ago(0), ago(6)], now, ReportRange.days7);
    expect(b7.length, 7);
    expect([b7.first, b7.last], [1, 2]);
    expect(sessionBuckets([ago(29)], now, ReportRange.days30).first, 1);
    expect(sessionBuckets(const [], now, ReportRange.days30).length, 30);
  });

  test('3 month chart groups into weeks and drops anything older', () {
    final b = sessionBuckets([ago(0), ago(1), ago(8), ago(89), ago(120)], now,
        ReportRange.days90);
    expect(b.length, 13);
    expect(b.last, 2); // today and yesterday share the newest week
    expect(b.reduce((a, c) => a + c), 4); // the 120-day-old one is excluded
  });

  test('medicine not marked done raises an alert with the count', () {
    final alerts = computeAlerts(
        sessions: const [], now: now, baseline: 2, overdueMedicines: 2);
    final a = alerts.firstWhere((x) => x.kind == AlertKind.medicineNotDone);
    expect(a.a, 2);
    expect(a.severity, AlertSeverity.attention);
  });

  test('low adherence needs enough reminders and a rate under half', () {
    List<AlertKind> kinds(AdherenceSummary w) => computeAlerts(
            sessions: const [], now: now, baseline: 2, weekAdherence: w)
        .map((a) => a.kind)
        .toList();
    expect(kinds(const AdherenceSummary(10, 3)), contains(AlertKind.lowAdherence));
    expect(kinds(const AdherenceSummary(10, 6)), isNot(contains(AlertKind.lowAdherence)));
    expect(kinds(const AdherenceSummary(4, 0)), isNot(contains(AlertKind.lowAdherence)));
  });

  test('summary text contains the figures and the non-medical note', () {
    final text = buildSummary(
      lang: 'en',
      name: 'Dada',
      range: ReportRange.days7,
      sessionsInRange: [s(ago(1), correct: 9), s(ago(2), correct: 7)],
      adherence: const AdherenceSummary(14, 11),
      alerts: const [
        EngagementAlert(AlertKind.inactive, AlertSeverity.attention, a: 3)
      ],
      gameNames: const {'attention': 'Find the target'},
    );
    expect(text, contains('Dada'));
    expect(text, contains('Last 7 days'));
    expect(text, contains('Find the target: 2 games, 80%'));
    expect(text, contains('11 of 14'));
    expect(text, contains('Has not played for 3 days'));
    expect(text, contains('not a medical assessment'));
    expect(text, isNot(contains('+91'))); // no phone numbers in a summary
  });

  test('reminder type is unused here but kind enum still compiles', () {
    expect(ReminderKind.values.length, 4);
  });
}
