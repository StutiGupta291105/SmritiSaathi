import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adherence.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/profile/profile_flow.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:smriti_assist/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Notifications need the phone's plugin, which tests do not have.
class _NoopNotifier extends ReminderNotifier {
  _NoopNotifier(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}

void main() {
  late Database raw;
  late AppDatabase db;
  late String pid;
  var done = false;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    final a = await db.createAccount(
        phone: '+919876543210', role: 'patient', name: 'Asha Devi');
    pid = await db.createPatient(
        accountId: a,
        phone: '+919876543210',
        displayName: 'Asha Devi',
        baselineLevel: 2,
        language: 'en',
        createdBy: 'x');
    await db.recordConsent(
        patientId: pid,
        purposes: {'gameplay': true, 'reminders': true},
        givenByName: 'Asha Devi',
        givenByRelation: 'self',
        noticeVersion: 'v2');
    done = false;
  });

  Future<Widget> app({int stage = 0, String? dob}) async {
    final p = (await db.patientById(pid))!;
    return MaterialApp(
        home: ProfileFlow(
      db: db,
      notifier: _NoopNotifier(db),
      onDone: () => done = true,
      patient: {...p, 'setup_stage': stage, 'dob': dob},
    ));
  }

  /// A phone-sized screen tall enough to build the whole form at once.
  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(800, 2600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  FilledButton next(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(const ValueKey('profileNext')));

  testWidgets('page 1 is one form with name and phone filled in', (t) async {
    tall(t);
    final w = (await t.runAsync(app))!;
    await t.pumpWidget(w);
    await t.pump();
    expect(find.text('Asha Devi'), findsWidgets);
    expect(find.text('+919876543210'), findsOneWidget);
    for (final k in ['profileName', 'profilePhone', 'profileEmail', 'profileCity', 'profileState', 'profileLanguage']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.text('1/5  ·  About you'), findsOneWidget);
    // Date of birth is the one thing that must be chosen.
    expect(next(t).onPressed, isNull);
  });

  testWidgets('a bad email blocks Next, a good one does not', (t) async {
    final w = (await t.runAsync(() => app(dob: '1948-03-02')))!;
    await t.pumpWidget(w);
    await t.pump();
    expect(next(t).onPressed, isNotNull);
    await t.enterText(find.byKey(const ValueKey('profileEmail')), 'not-an-email');
    await t.pump();
    expect(next(t).onPressed, isNull);
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('profileEmail')), 'asha@example.com');
    await t.pump();
    expect(next(t).onPressed, isNotNull);
  });

  testWidgets('Next saves the form and moves to family members', (t) async {
    tall(t);
    final w = (await t.runAsync(() => app(dob: '1948-03-02')))!;
    await t.pumpWidget(w);
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('profileName')), 'Asha D Sharma');
    await t.enterText(find.byKey(const ValueKey('profileEmail')), 'asha@example.com');
    await t.enterText(find.byKey(const ValueKey('profileCity')), 'Deoghar');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('profileNext')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(find.text('2/5  ·  Family members'), findsOneWidget);
    await t.runAsync(() async {
      final p = (await raw.query('patients')).single;
      expect(p['display_name'], 'Asha D Sharma');
      expect(p['email'], 'asha@example.com');
      expect(p['city'], 'Deoghar');
      expect(p['setup_stage'], 1);
    });
  });

  testWidgets('doctor and caregiver have a page each', (t) async {
    final w2 = (await t.runAsync(() => app(stage: 2)))!;
    await t.pumpWidget(w2);
    await t.pump();
    expect(find.text('3/5  ·  Doctor details'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final w3 = (await t.runAsync(() => app(stage: 3)))!;
    await t.pumpWidget(w3);
    await t.pump();
    expect(find.text('4/5  ·  Caregiver details'), findsOneWidget);
  });

  testWidgets('caregiver page takes a Care ID, not a phone number', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1500));
    await t.runAsync(() => db.recordConsent(
        patientId: pid,
        purposes: {'caregiver_share': true},
        givenByName: 'Asha Devi',
        givenByRelation: 'self',
        noticeVersion: 'v2'));
    final w = (await t.runAsync(() => app(stage: 3)))!;
    await t.pumpWidget(w);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(find.text('Mobile number'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Ravi');
    await t.enterText(find.byKey(const ValueKey('careId_caregiver')), 'hello');
    await t.pump();
    expect(find.textContaining('not a Care ID'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save invite')).onPressed, isNull);
    // a doctor's ID does not fit the caregiver page
    await t.enterText(find.byKey(const ValueKey('careId_caregiver')), 'dr-ab23xy');
    await t.pump();
    expect(find.textContaining('not a Care ID'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('careId_caregiver')), 'cg-ab23xy');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save invite'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    final links = (await t.runAsync(() => db.listCareLinks(pid)))!;
    expect(links.single['professional_id'], 'CG-AB23XY');
    expect(links.single['phone'], isNull);
  });

  group('changing things later from Settings', () {
    Future<Widget> edit(int stage, {ServerHooks? hooks}) async {
      final p = (await db.patientById(pid))!;
      return MaterialApp(
          home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => ProfileFlow(
                        db: db,
                        notifier: _NoopNotifier(db),
                        hooks: hooks,
                        editStage: stage,
                        patient: {...p, 'setup_stage': 5},
                        onDone: () => done = true,
                      ))));
    }

    Future<void> consentCaregiver() => db.recordConsent(
        patientId: pid,
        purposes: {'caregiver_share': true},
        givenByName: 'Asha Devi',
        givenByRelation: 'self',
        noticeVersion: 'v2');

    testWidgets('one page opens with its own Save and leaves setup progress alone', (t) async {
      tall(t);
      final w = (await t.runAsync(() => edit(0)))!;
      await t.pumpWidget(w);
      await t.pump();
      expect(find.byKey(const ValueKey('profileNext')), findsOneWidget);
      expect(find.text('1/5  ·  About you'), findsNothing); // no step counter
      await t.enterText(find.byKey(const ValueKey('profileCity')), 'Pune');
      await t.pump();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a caregiver can be removed and another added', (t) async {
      tall(t);
      await t.runAsync(consentCaregiver);
      final id = (await t.runAsync(() => db.addCareInvite(
          patientId: pid,
          kind: 'caregiver',
          name: 'Ravi',
          professionalId: 'CG-AB23XY',
          by: 'Asha')))!;
      await t.runAsync(() => db.setCareLinkServerId(id, 'srv-1'));
      final ended = <String>[];
      final hooks = ServerHooks(
          syncNow: () async {},
          eraseRemote: (_) async => true,
          endLink: (sid) async {
            ended.add(sid);
            return true;
          });
      final w = (await t.runAsync(() => edit(3, hooks: hooks)))!;
      await t.pumpWidget(w);
      for (var i = 0; i < 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await t.pump();
      }
      expect(find.textContaining('Ravi'), findsOneWidget);
      await t.tap(find.byKey(ValueKey('remove_$id')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Remove'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(ended, ['srv-1']); // cut off on the server first
      expect(find.textContaining('Ravi'), findsNothing);
      // the form to add someone new is there
      await t.enterText(find.byType(TextField).first, 'Meena');
      await t.enterText(find.byKey(const ValueKey('careId_caregiver')), 'cg-zz23xy');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Save invite'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump();
      final links = (await t.runAsync(() => db.listCareLinks(pid)))!;
      expect(links.map((l) => [l['name'], l['status']]).toList(),
          [['Ravi', 'revoked'], ['Meena', 'pending']]);
    });

    testWidgets('when the server cannot be reached nobody is removed', (t) async {
      tall(t);
      await t.runAsync(consentCaregiver);
      final id = (await t.runAsync(() => db.addCareInvite(
          patientId: pid,
          kind: 'caregiver',
          name: 'Ravi',
          professionalId: 'CG-AB23XY',
          by: 'Asha')))!;
      await t.runAsync(() => db.setCareLinkServerId(id, 'srv-1'));
      final hooks = ServerHooks(
          syncNow: () async {},
          eraseRemote: (_) async => true,
          endLink: (_) async => false);
      final w = (await t.runAsync(() => edit(3, hooks: hooks)))!;
      await t.pumpWidget(w);
      for (var i = 0; i < 3; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await t.pump();
      }
      await t.tap(find.byKey(ValueKey('remove_$id')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Remove'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(find.text('You need an internet connection to remove them.'), findsOneWidget);
      expect(find.textContaining('Ravi'), findsOneWidget);
      final links = (await t.runAsync(() => db.listCareLinks(pid)))!;
      expect(links.single['status'], 'pending');
    });
  });

  testWidgets('routine page: add a daily routine, delete it, then Save finishes',
      (t) async {
    final w = (await t.runAsync(() => app(stage: 4)))!;
    await t.pumpWidget(w);
    // The consent gate and the reminder list both read the database.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(find.text('5/5  ·  Daily routine'), findsWidgets);
    expect(find.text('Reminders and important dates'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await t.ensureVisible(find.byKey(const ValueKey('addRoutine')));
    await t.tap(find.byKey(const ValueKey('addRoutine')));
    await t.pumpAndSettle();
    // The dialog asks who is making the change, pre-filled with the patient.
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final rows = await raw.query('reminders');
      expect(rows.length, 1);
      expect(rows.single['kind'], 'medicine');
      expect(rows.single['days_mask'], 127);
    });
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    await t.tap(find.byIcon(Icons.delete_outline_rounded));
    for (var i = 0; i < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

    await t.tap(find.byKey(const ValueKey('profileNext')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(done, isTrue);
    await t.runAsync(() async {
      expect((await raw.query('patients')).single['setup_stage'], 5);
    });
  });

  group('birthdays and events', () {
    Reminder r(ReminderKind k, DateTime d) => Reminder(
        id: 'r', kind: k, label: '', hour: 9, minute: 0, onDate: d);

    test('a birthday comes round every year, an event happens once', () {
      final bday = r(ReminderKind.birthday, DateTime(1948, 3, 2));
      expect(nextOccurrences(bday, DateTime(2026, 1, 1)).single,
          DateTime(2026, 3, 2, 9));
      expect(nextOccurrences(bday, DateTime(2026, 3, 2, 10)).single,
          DateTime(2027, 3, 2, 9));
      expect(occursOn(bday, DateTime(2031, 3, 2)), isTrue);
      expect(occursOn(bday, DateTime(2031, 3, 3)), isFalse);

      final event = r(ReminderKind.event, DateTime(2026, 5, 5));
      expect(nextOccurrences(event, DateTime(2026, 1, 1)).single,
          DateTime(2026, 5, 5, 9));
      expect(nextOccurrences(event, DateTime(2026, 6, 1)), isEmpty);
      expect(occursOn(event, DateTime(2027, 5, 5)), isFalse);
    });
  });
}
