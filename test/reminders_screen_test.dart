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

  testWidgets('three tabs: Medicines, Routine, Reminders', (t) async {
    await open(t);
    for (final l in ['Medicines', 'Routine', 'Reminders']) {
      expect(find.text(l), findsWidgets);
    }
    expect(find.text('Today'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Metformin 500 mg'), findsOneWidget); // first tab: medicines only
    expect(find.text('Evening walk'), findsNothing);
    await t.tap(find.byKey(const ValueKey('remTab1')));
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

  testWidgets('there is no water tracker; water reminders sit under Routine', (t) async {
    await open(t);
    expect(find.text('Water Tracker'), findsNothing);
    expect(find.byKey(const ValueKey('drinkGlass')), findsNothing);
    await t.tap(find.byKey(const ValueKey('remTab1')));
    await t.pumpAndSettle();
    expect(find.text('Morning water'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
  });

  testWidgets('the Reminders tab lists appointments, events and important dates, soonest first', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab2')));
    await t.pumpAndSettle();
    final order = ['Dr Rao clinic', 'Sita birthday', 'Family lunch']; // in 3, 4 and 8 days
    final ys = [for (final n in order) t.getTopLeft(find.text(n)).dy];
    expect(ys, [...ys]..sort());
    expect(find.text('Evening walk'), findsNothing);
    expect(find.text('Metformin 500 mg'), findsNothing);
  });

  testWidgets('the add button offers only what belongs to the tab', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab2')));
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

  testWidgets('a patient can add a routine from a quick template and it shows in the list', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab1'))); // Routine
    await t.pumpAndSettle();
    expect(find.text('Evening walk'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('addReminder')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // reads the patient first
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('tpl_tplLunch')));
    await t.tap(find.byKey(const ValueKey('tpl_tplLunch')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    final rows = (await t.runAsync(() => db.listReminders(pid)))!;
    expect(rows.where((r) => r.label == 'Lunch').length, 1);
  });

  testWidgets('a patient can add a typed routine, and a medicine with a name', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('addReminder')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // reads the patient first
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Water the plants');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text('Water the plants'), findsOneWidget);
    // Medicines tab: the dialog opens on Medicine and needs a name
    await t.tap(find.byKey(const ValueKey('remTab0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('addReminder')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // reads the patient first
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pump();
    expect(find.text('Please enter the medicine name.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('rxName')), 'Vitamin D');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text('Vitamin D'), findsOneWidget);
  });

  testWidgets('a routine can be set for chosen days: S M T W T F S, and Every day selects all', (t) async {
    t.view.physicalSize = const Size(800, 2200);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await open(t);
    await t.tap(find.byKey(const ValueKey('remTab1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('addReminder')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    // the seven day circles read S M T W T F S, all on by default
    for (final l in ['S', 'M', 'T', 'W', 'F']) {
      expect(find.text(l), findsWidgets);
    }
    expect(find.text('Every day'), findsWidgets);
    expect(find.byKey(const ValueKey('daysSummary')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('day6'))); // Sunday off
    await t.tap(find.byKey(const ValueKey('day1'))); // Tuesday off
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('daysSummary'))).data, 'Mon, Wed, Thu, Fri, Sat');
    await t.tap(find.byKey(const ValueKey('daysAll'))); // select all again
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('daysSummary'))).data, 'Every day');
    // weekends only: turn weekdays off one by one; the last day cannot be turned off
    for (final bit in [0, 1, 2, 3, 4]) {
      await t.tap(find.byKey(ValueKey('day$bit')));
    }
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('daysSummary'))).data, 'Sat, Sun');
    await t.tap(find.byKey(const ValueKey('day5')));
    await t.tap(find.byKey(const ValueKey('day6'))); // would leave none: ignored
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('daysSummary'))).data, 'Sun');
    await t.tap(find.byKey(const ValueKey('day5'))); // Saturday back on
    await t.pump();
    await t.enterText(find.byType(TextField).last, 'Weekend walk');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    final saved = (await t.runAsync(() => db.listReminders(pid)))!.firstWhere((r) => r.label == 'Weekend walk');
    expect(saved.daysMask, (1 << 5) | (1 << 6)); // Saturday and Sunday
    expect(find.textContaining('Sat, Sun'), findsOneWidget); // and the list says so
  });
}
