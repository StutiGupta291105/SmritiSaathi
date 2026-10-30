import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/reminders/reminders_screen.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoopNotifier extends ReminderNotifier {
  _NoopNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}

void main() {
  late AppDatabase db;
  late String pid;

  setUp(() async {
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    final a = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'Asha');
    pid = await db.createPatient(
        accountId: a, phone: '+919876543210', displayName: 'Asha',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.recordConsent(
        patientId: pid,
        purposes: {'gameplay': true, 'reminders': true, 'sync': true},
        givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');
  });

  Future<void> add(ReminderKind k, String label, {int h = 9, DateTime? on}) => db.addReminder(
      patientId: pid, kind: k, label: label, hour: h, minute: 0, onDate: on, createdBy: 'Asha');

  Future<void> open(WidgetTester t) async {
    await t.runAsync(() async {
      await add(ReminderKind.medicine, 'Metformin 500 mg');
      await add(ReminderKind.hydration, 'Morning water', h: 8);
      await add(ReminderKind.activity, 'Evening walk', h: 18);
      final in3 = DateTime.now().add(const Duration(days: 3));
      await add(ReminderKind.appointment, 'Dr Rao clinic', h: 11, on: DateTime(in3.year, in3.month, in3.day));
      await add(ReminderKind.event, 'Family lunch', h: 13, on: DateTime(in3.year, in3.month, in3.day + 5));
      await add(ReminderKind.birthday, 'Sita birthday', h: 9, on: DateTime(1950, in3.month, in3.day + 1));
    });
    await t.pumpWidget(MaterialApp(
        home: RemindersScreen(db: db, notifier: _NoopNotifier(db), patientId: pid, language: 'en', embedded: true)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
  }

  testWidgets('four tabs: Medicines, Water Tracker, Routine, Reminders', (t) async {
    await open(t);
    for (final l in ['Medicines', 'Water Tracker', 'Routine', 'Reminders']) {
      expect(find.text(l), findsWidgets);
    }
    expect(find.text('Today'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Metformin 500 mg'), findsOneWidget); // first tab: medicines only
    expect(find.text('Evening walk'), findsNothing);
    await t.tap(find.byKey(const ValueKey('remTab2')));
    await t.pumpAndSettle();
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsNothing);
  });

  testWidgets('a medicine can be marked as taken and taken back', (t) async {
    await open(t);
    expect(find.text('Mark as taken'), findsOneWidget);
    final id = (await t.runAsync(() => db.listReminders(pid)))!
        .firstWhere((r) => r.kind == ReminderKind.medicine).id;
    await t.tap(find.byKey(ValueKey('taken_$id')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('Taken'), findsOneWidget);
    await t.tap(find.byKey(ValueKey('taken_$id')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('Mark as taken'), findsOneWidget);
  });

  testWidgets('water tracker counts glasses, is remembered, and a slip can be undone', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab1')));
    await t.pumpAndSettle();
    expect(find.text('0 of 8 glasses'), findsOneWidget);
    expect(find.text('Morning water'), findsOneWidget); // water reminders are listed below
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('drinkGlass')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
    }
    expect(find.text('3 of 8 glasses'), findsOneWidget);
    expect((await t.runAsync(() => db.waterToday(pid))), 3);
    await t.tap(find.byKey(const ValueKey('glass2'))); // the last full glass
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.text('2 of 8 glasses'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('glass0'))); // not the last: ignored
    await t.pump();
    expect(find.text('2 of 8 glasses'), findsOneWidget);
  });

  testWidgets('the Reminders tab lists appointments, events and important dates, soonest first', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab3')));
    await t.pumpAndSettle();
    final order = ['Dr Rao clinic', 'Sita birthday', 'Family lunch']; // in 3, 4 and 8 days
    final ys = [for (final n in order) t.getTopLeft(find.text(n)).dy];
    expect(ys, [...ys]..sort());
    expect(find.text('Evening walk'), findsNothing);
    expect(find.text('Metformin 500 mg'), findsNothing);
  });

  testWidgets('the add button offers only what belongs to the tab', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab3')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('addReminder')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<ReminderKind>));
    await t.pumpAndSettle();
    expect(find.text('Appointment'), findsWidgets);
    expect(find.text('Medicine'), findsNothing);
    expect(find.text('Water'), findsNothing);
  });
}
