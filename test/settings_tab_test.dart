import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/features/shell/profile_tab.dart';
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
  var loggedOut = false;

  setUp(() async {
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
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
        purposes: {'gameplay': true, 'family_contacts': true},
        givenByName: 'Asha Devi',
        givenByRelation: 'self',
        noticeVersion: 'v2');
    await db.updateProfileBasics(
        patientId: pid,
        displayName: 'Asha Devi',
        email: 'asha@example.com',
        city: 'Guwahati',
        state: 'Assam',
        dob: DateTime(1950, 3, 2),
        language: 'en',
        by: 'x');
    loggedOut = false;
  });

  Future<void> pumpTab(WidgetTester t) async {
    final p = (await t.runAsync(() => db.patientById(pid)))!;
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProfileTab(
                db: db,
                notifier: _NoopNotifier(db),
                patient: p,
                onChanged: () {},
                onLogout: () => loggedOut = true))));
    await t.pump();
  }

  testWidgets('settings lists four rows, logout and the footer', (t) async {
    await pumpTab(t);
    for (final k in ['rowProfile', 'rowHelp', 'rowAbout', 'rowSos']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('About App'), findsOneWidget);
    expect(find.text('Emergency SOS'), findsOneWidget);
    expect(find.textContaining('MDoNER Digital Health'), findsOneWidget);
    await t.tap(find.text('Log out'));
    expect(loggedOut, isTrue);
  });

  testWidgets('Profile opens the patient details', (t) async {
    await pumpTab(t);
    await t.tap(find.byKey(const ValueKey('rowProfile')));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(find.text('Asha Devi'), findsWidgets);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Guwahati'), findsOneWidget);
    expect(find.text('Assam'), findsOneWidget);
    expect(find.byKey(const ValueKey('languageRow')), findsOneWidget);
  });

  testWidgets('Help, About and SOS open', (t) async {
    await pumpTab(t);
    for (final k in ['rowHelp', 'rowAbout', 'rowSos']) {
      await t.tap(find.byKey(ValueKey(k)));
      await t.pump();
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      if (k == 'rowSos') {
        expect(find.byKey(const ValueKey('sosCall112')), findsOneWidget);
      }
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });
}
