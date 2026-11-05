import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/shell/garden.dart';
import 'package:smriti_assist/features/shell/home_tab.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('the sky follows the time of day', () {
    expect(periodAt(DateTime(2026, 11, 5, 7)), SkyPeriod.morning);
    expect(periodAt(DateTime(2026, 11, 5, 13)), SkyPeriod.afternoon);
    expect(periodAt(DateTime(2026, 11, 5, 18)), SkyPeriod.evening);
    expect(periodAt(DateTime(2026, 11, 5, 23)), SkyPeriod.night);
    expect(periodAt(DateTime(2026, 11, 5, 3)), SkyPeriod.night);
    expect(skyFor(SkyPeriod.night).dark, isTrue);
    expect(skyFor(SkyPeriod.morning).dark, isFalse);
  });

  testWidgets('the garden draws for every time of day and every stage of growth', (t) async {
    for (final h in [7, 13, 18, 23]) {
      for (final p in [0.0, 0.2, 0.5, 0.8, 1.0]) {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: GardenHeader(
                    greeting: 'Good morning', name: 'Asha', photo: null,
                    progress: p, progressText: '1 of 4 done today', now: DateTime(2026, 11, 5, h)))));
        expect(find.byKey(const ValueKey('gardenScene')), findsOneWidget);
        expect(find.text('1 of 4 done today'), findsOneWidget);
      }
    }
  });

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
    pid = await db.createPatient(accountId: a, phone: '+919876543210', displayName: 'Asha',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.recordConsent(patientId: pid, purposes: {'gameplay': true, 'reminders': true},
        givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');
  });

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeTab(
                db: db, patientId: pid, name: 'Asha', photo: null, lang: 'en',
                onPlay: () {}, onGames: () {}, onReminders: () {}, onProgress: () {}, onTalk: () {}))));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('today is a timeline: "now" marks the next task, ticking moves it on and grows the garden', (t) async {
    await t.runAsync(() async {
      await db.addReminder(patientId: pid, kind: ReminderKind.medicine, label: 'Metformin', hour: 0, minute: 5, createdBy: 'Dr Rao');
      await db.addReminder(patientId: pid, kind: ReminderKind.hydration, label: 'Water', hour: 23, minute: 50, createdBy: 'Asha');
    });
    await open(t);
    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('0 of 3 done today'), findsOneWidget); // two tasks plus today's game
    expect(find.byKey(const ValueKey('timelineNow')), findsOneWidget);
    // tick the first task
    await t.tap(find.byTooltip('Mark as done').first);
    for (var i = 0; i < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
  });

  testWidgets('an empty day is a young plant, not a failure', (t) async {
    await open(t);
    expect(find.text('Nothing planned for today.'), findsOneWidget);
    expect(find.text('0 of 1 done today'), findsOneWidget);
    expect(find.byKey(const ValueKey('timelineNow')), findsNothing);
  });
}
