import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/features/remote/care_timeline.dart';

Map<String, dynamic> _c(String id, String label, int h, int m,
        {int mask = 127, String? on, String kind = 'activity'}) =>
    {'id': id, 'kind': kind, 'label': label, 'hour': h, 'minute': m, 'days_mask': mask, 'on_date': on};

void main() {
  final wed = DateTime(2026, 5, 6, 12, 0); // a Wednesday

  test('only what falls on today, soonest first, with the patient and who added it', () {
    final items = todayItems([
      _c('a', 'Evening walk', 18, 0),
      _c('b', 'Morning medicine', 8, 0, kind: 'medicine'),
      _c('c', 'Mondays only', 9, 0, mask: 1), // Monday
      _c('d', 'Wednesday dentist', 15, 30, mask: 0, on: '2026-05-06', kind: 'appointment'),
      _c('e', 'Next week visit', 10, 0, mask: 0, on: '2026-05-13', kind: 'appointment'),
      _c('f', 'Last week visit', 10, 0, mask: 0, on: '2026-04-29', kind: 'appointment'),
    ], wed, patient: 'Asha');
    expect(items.map((x) => x.label), ['Morning medicine', 'Wednesday dentist', 'Evening walk']);
    expect(items.map((x) => x.kind),
        [ReminderKind.medicine, ReminderKind.appointment, ReminderKind.activity]);
    expect(items.first.patient, 'Asha');
  });

  test('a past time today is still listed (it shows as done), and an unknown kind falls back', () {
    final items = todayItems([_c('a', 'Early walk', 6, 0), _c('b', 'Odd', 7, 0, kind: 'mystery')], wed);
    expect(items.map((x) => x.label), ['Early walk', 'Odd']);
    expect(items.last.kind, ReminderKind.activity);
  });

  test('nothing is planned gives an empty list', () {
    expect(todayItems(const [], wed), isEmpty);
  });

  testWidgets('a long day shows a window around now, not every item', (t) async {
    final now = DateTime(2026, 5, 6, 12, 0);
    final items = [
      for (var h = 6; h <= 21; h++) TodayItem(DateTime(2026, 5, 6, h, 0), ReminderKind.activity, 'Item $h'),
    ];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CareTimeline(
                    title: 'Today', empty: 'none', items: items, lang: 'en', now: now)))));
    expect(find.textContaining('Item '), findsNWidgets(6));
    expect(find.text('Item 11'), findsOneWidget); // the last one done
    expect(find.text('Item 12'), findsOneWidget); // now
    expect(find.text('Item 16'), findsOneWidget);
    expect(find.text('Item 6'), findsNothing);
    expect(find.text('Item 21'), findsNothing);
    expect(find.byKey(const ValueKey('timelineNow')), findsOneWidget);
  });

  testWidgets('empty day shows the hint', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CareTimeline(
                title: 'Today', empty: 'Nothing today', items: const [], lang: 'en', now: DateTime(2026, 5, 6)))));
    expect(find.text('Nothing today'), findsOneWidget);
  });
}
