import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/engagement_alerts.dart';

SessionRecord s(DateTime t,
        {String game = 'memory_match',
        int start = 2,
        int end = 2,
        int trials = 10,
        int correct = 8}) =>
    SessionRecord(
        game: game,
        endedAt: t,
        startLevel: start,
        endLevel: end,
        trials: trials,
        correct: correct);

final now = DateTime(2026, 3, 20, 12);
DateTime ago(int days) => DateTime(2026, 3, 20 - days, 10);

List<AlertKind> kinds(List<EngagementAlert> a) => a.map((e) => e.kind).toList();

void main() {
  test('no history means no alerts', () {
    expect(computeAlerts(sessions: const [], now: now, baseline: 2), isEmpty);
  });

  test('regular play gives no alerts', () {
    final sessions = [for (var d = 0; d < 10; d++) s(ago(d))];
    expect(computeAlerts(sessions: sessions, now: now, baseline: 2), isEmpty);
  });

  test('3+ days without playing, after regular use, raises an inactive alert',
      () {
    final sessions = [for (var d = 4; d < 12; d++) s(ago(d))];
    final alerts = computeAlerts(sessions: sessions, now: now, baseline: 2);
    expect(kinds(alerts), contains(AlertKind.inactive));
    expect(alerts.firstWhere((a) => a.kind == AlertKind.inactive).a, 4);
  });

  test('a new user who has played little is not flagged as inactive', () {
    final sessions = [s(ago(6)), s(ago(5))];
    expect(
        kinds(computeAlerts(sessions: sessions, now: now, baseline: 2)),
        isNot(contains(AlertKind.inactive)));
  });

  test('half as many sessions as the week before raises fewerSessions', () {
    final sessions = [
      for (var d = 7; d < 13; d++) s(ago(d)), // 6 in the earlier week
      s(ago(1)), s(ago(2)), // 2 in the last week
    ];
    final alerts = computeAlerts(sessions: sessions, now: now, baseline: 2);
    final a = alerts.firstWhere((x) => x.kind == AlertKind.fewerSessions);
    expect([a.a, a.b], [2, 6]);
  });

  test('a clear accuracy dip is reported with its size', () {
    final sessions = [
      for (var d = 9; d >= 4; d--) s(ago(d), correct: 9), // 90%
      s(ago(2), correct: 5), s(ago(1), correct: 5), s(ago(0), correct: 5), // 50%
    ];
    final alerts = computeAlerts(sessions: sessions, now: now, baseline: 2);
    final a = alerts.firstWhere((x) => x.kind == AlertKind.accuracyDip);
    expect(a.a, 40);
  });

  test('normal ups and downs are not an accuracy dip', () {
    final sessions = [
      for (var d = 9; d >= 4; d--) s(ago(d), correct: 8),
      s(ago(2), correct: 7), s(ago(1), correct: 8), s(ago(0), correct: 7),
    ];
    expect(kinds(computeAlerts(sessions: sessions, now: now, baseline: 2)),
        isNot(contains(AlertKind.accuracyDip)));
  });

  test('three sessions ending at the top of the band suggest raising baseline',
      () {
    final sessions = [for (var d = 2; d >= 0; d--) s(ago(d), end: 3)];
    final alerts = computeAlerts(sessions: sessions, now: now, baseline: 2);
    expect(kinds(alerts), contains(AlertKind.suggestRaiseBaseline));
    expect(alerts.last.severity, AlertSeverity.info);
  });

  test('attention alerts are listed before suggestions', () {
    final sessions = [
      for (var d = 11; d >= 4; d--) s(ago(d), end: 3),
    ];
    final alerts = computeAlerts(sessions: sessions, now: now, baseline: 2);
    expect(alerts.first.severity, AlertSeverity.attention);
  });

  test('summary groups by game with average accuracy', () {
    final out = summarizeByGame([
      s(ago(1), game: 'attention', correct: 10),
      s(ago(2), game: 'attention', correct: 6),
      s(ago(1), game: 'routine', correct: 8),
    ]);
    expect(out.map((g) => g.game), ['attention', 'routine']);
    expect(out.first.sessions, 2);
    expect(out.first.accuracy, closeTo(0.8, 1e-9));
  });
}
