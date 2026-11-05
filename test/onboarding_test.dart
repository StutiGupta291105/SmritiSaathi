import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/onboarding/onboarding_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database raw;
  late AppDatabase db;
  var done = false;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    done = false;
  });

  Widget app() => MaterialApp(
          home: OnboardingScreen(
        db: db,
        account: const {'id': 'a1', 'phone': '9999999999', 'name': 'Asha Devi'},
        lang: 'en',
        onDone: () => done = true,
      ));

  FilledButton cont(WidgetTester t) =>
      t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));

  testWidgets('Allow turns into a green tick, and tapping it takes it back',
      (t) async {
    await t.pumpWidget(app());
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    await t.tap(find.byKey(const ValueKey('allow_reminders')));
    await t.pump();
    expect(find.byKey(const ValueKey('allowed_reminders')), findsOneWidget);
    expect(find.byKey(const ValueKey('allow_reminders')), findsNothing);
    await t.tap(find.byKey(const ValueKey('allowed_reminders')));
    await t.pump();
    expect(find.byKey(const ValueKey('allow_reminders')), findsOneWidget);
  });

  testWidgets('cannot continue until saving results is allowed', (t) async {
    await t.pumpWidget(app());
    expect(cont(t).onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('allow_reminders')));
    await t.pump();
    expect(cont(t).onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('allow_gameplay')));
    await t.pump();
    expect(cont(t).onPressed, isNotNull);
  });

  testWidgets('records consent for the chosen purposes, given by the person',
      (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const ValueKey('allow_gameplay')));
    await t.tap(find.byKey(const ValueKey('allow_reminders')));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await t.pump();
    expect(done, isTrue);
    await t.runAsync(() async {
      final p = (await raw.query('patients')).single;
      expect(p['baseline_level'], 2);
      final state = await db.consentState(p['id'] as String);
      expect(state['gameplay'], isTrue);
      expect(state['reminders'], isTrue);
      expect(state['doctor_share'] ?? false, isFalse);
      final log = await raw.query('consents');
      expect(log.every((r) => r['given_by_relation'] == 'self'), isTrue);
      expect(log.every((r) => r['given_by_name'] == 'Asha Devi'), isTrue);
    });
  });
}
