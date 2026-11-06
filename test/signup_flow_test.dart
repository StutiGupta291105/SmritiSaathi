import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/data/session_store.dart';
import 'package:smriti_assist/features/auth/auth_screen.dart';
import 'package:smriti_assist/features/onboarding/permissions_screen.dart';
import 'package:smriti_assist/services/app_permissions.dart';
import 'package:smriti_assist/features/auth/welcome_screen.dart';
import 'package:smriti_assist/features/onboarding/personal_details_screen.dart';
import 'package:smriti_assist/main.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Session extends SessionStore {
  _Session([this.id]);
  String? id;
  @override
  Future<String?> read() async => id;
  @override
  Future<void> write(String accountId) async => id = accountId;
  @override
  Future<void> clear() async => id = null;
}

class _Asker implements PermissionAsker {
  int calls = 0;
  @override
  Future<void> askAll(ReminderNotifier notifier) async => calls++;
}

class _Noop extends ReminderNotifier {
  _Noop(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}

void main() {
  late Database raw;
  late AppDatabase db;
  late _Asker asker;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    asker = _Asker();
  });
  tearDown(() => raw.close());

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<String> newAccount(WidgetTester t, {String name = 'Asha Devi'}) async =>
      (await t.runAsync(() => db.createAccount(phone: '+919876543210', role: 'patient', name: name)))!;

  Future<void> pickDob(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const ValueKey('detailsDob')));
    await t.tap(find.byKey(const ValueKey('detailsDob')));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  group('welcome and sign-in', () {
    testWidgets('the welcome screen offers Get Started and Login, as before', (t) async {
      var made = false, login = false;
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: WelcomeScreen(
              lang: 'en', onGetStarted: () => made = true, onLogin: () => login = true)));
      await t.tap(find.text('Get Started'));
      await t.tap(find.text('Log in'));
      expect([made, login], [true, true]);
    });

    testWidgets('sign-up asks role, name and mobile number, then a code', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1300));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: AuthScreen(
              db: db, otp: DevOtpService(), session: _Session(), lang: 'en',
              onLangChanged: (_) {}, onLoggedIn: () {}, initialSignUp: true)));
      expect(find.byKey(const ValueKey('roleDropdown')), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'Asha Devi');
      await t.enterText(find.byType(TextField).at(1), '+919876543210');
      await t.tap(find.widgetWithText(FilledButton, 'Send OTP'));
      for (var i = 0; i < 3; i++) {
        await settle(t);
      }
      expect(find.text('Enter the 6-digit OTP'), findsOneWidget);
    });
  });

  group('personal details (the last step of creating a patient account)', () {
    Future<void> open(WidgetTester t, String accountId, {Map<String, Object?>? existing, VoidCallback? done}) async {
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: PersonalDetailsScreen(
              db: db,
              account: {'id': accountId, 'phone': '+919876543210', 'name': 'Asha Devi'},
              lang: 'en',
              existing: existing,
              onDone: done ?? () {})));
    }

    testWidgets('it asks for date of birth, email, city, state and language, and the one consent', (t) async {
      final id = await newAccount(t);
      await open(t, id);
      expect(find.byKey(const ValueKey('detailsDob')), findsOneWidget);
      expect(find.byKey(const ValueKey('detailsEmail')), findsOneWidget);
      expect(find.byKey(const ValueKey('detailsCity')), findsOneWidget);
      expect(find.byKey(const ValueKey('detailsState')), findsOneWidget);
      expect(find.byKey(const ValueKey('languageRow')), findsOneWidget);
      expect(find.byKey(const ValueKey('consentCore')), findsOneWidget);
      // the old long "Complete your profile" steps are not here
      expect(find.text('Family members'), findsNothing);
    });

    testWidgets('it cannot continue without a date of birth and the consent, nor with a bad email', (t) async {
      final id = await newAccount(t);
      await open(t, id);
      FilledButton go() => t.widget<FilledButton>(find.byKey(const ValueKey('detailsContinue')));
      expect(go().onPressed, isNull);
      await pickDob(t);
      expect(go().onPressed, isNull); // consent still missing
      await t.tap(find.byKey(const ValueKey('consentCore')));
      await t.pump();
      expect(go().onPressed, isNotNull);
      await t.enterText(find.byKey(const ValueKey('detailsEmail')), 'not an email');
      await t.pump();
      expect(go().onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('detailsEmail')), 'asha@example.com');
      await t.pump();
      expect(go().onPressed, isNotNull);
    });

    testWidgets('saving creates the patient with the details, the consent and a finished setup', (t) async {
      final id = await newAccount(t);
      var done = false;
      await open(t, id, done: () => done = true);
      await pickDob(t);
      await t.enterText(find.byKey(const ValueKey('detailsEmail')), 'asha@example.com');
      await t.enterText(find.byKey(const ValueKey('detailsCity')), 'Guwahati');
      await t.ensureVisible(find.byKey(const ValueKey('detailsState')));
      await t.tap(find.byKey(const ValueKey('detailsState')));
      await t.pumpAndSettle();
      await t.tap(find.text('Assam').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('consentCore')));
      await t.tap(find.byKey(const ValueKey('consentCore')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('detailsContinue')));
      await t.tap(find.byKey(const ValueKey('detailsContinue')));
      await settle(t);
      expect(done, isTrue);
      final p = (await t.runAsync(() => db.patientForAccount(id)))!;
      expect([p['email'], p['city'], p['state']], ['asha@example.com', 'Guwahati', 'Assam']);
      expect(p['dob'], isNotNull);
      expect(p['setup_stage'], 5); // straight to the dashboard
      expect(p['language'], 'en');
      final pid = p['id'] as String;
      Future<bool> has(String purpose) async => (await t.runAsync(() => db.hasConsent(pid, purpose)))!;
      expect([await has('gameplay'), await has('reminders')], [true, true]);
      // sharing with the care team was not ticked, so it is off
      expect([await has('sync'), await has('doctor_share'), await has('caregiver_share'), await has('family_contacts')],
          [false, false, false, false]);
    });

    testWidgets('ticking the care team box also allows sharing with the people the patient invites', (t) async {
      final id = await newAccount(t);
      await open(t, id);
      await pickDob(t);
      for (final k in ['consentCore', 'consentCare']) {
        await t.ensureVisible(find.byKey(ValueKey(k)));
        await t.tap(find.byKey(ValueKey(k)));
        await t.pump();
      }
      await t.ensureVisible(find.byKey(const ValueKey('detailsContinue')));
      await t.tap(find.byKey(const ValueKey('detailsContinue')));
      await settle(t);
      final pid = (await t.runAsync(() => db.patientForAccount(id)))!['id'] as String;
      for (final p in ['sync', 'doctor_share', 'caregiver_share']) {
        expect(await t.runAsync(() => db.hasConsent(pid, p)), isTrue, reason: p);
      }
    });

    testWidgets('the language chosen here is the one the patient is saved with', (t) async {
      final id = await newAccount(t);
      await open(t, id);
      await t.ensureVisible(find.byKey(const ValueKey('languageRow')));
      await t.tap(find.byKey(const ValueKey('languageRow')));
      await t.pumpAndSettle();
      await t.tap(find.text('हिन्दी').first);
      await t.pumpAndSettle();
      expect(find.text('आपके बारे में थोड़ा'), findsOneWidget); // the page switched language
      await pickDob(t);
      await t.ensureVisible(find.byKey(const ValueKey('consentCore')));
      await t.tap(find.byKey(const ValueKey('consentCore')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('detailsContinue')));
      await t.tap(find.byKey(const ValueKey('detailsContinue')));
      await settle(t);
      expect((await t.runAsync(() => db.patientForAccount(id)))!['language'], 'hi');
    });

    testWidgets('an earlier profile without a date of birth is asked for it, with no new consent', (t) async {
      final id = await newAccount(t);
      final pid = (await t.runAsync(() => db.createPatient(
          accountId: id, phone: '+919876543210', displayName: 'Asha Devi',
          baselineLevel: 2, language: 'en', createdBy: 'x')))!;
      final existing = (await t.runAsync(() => db.patientById(pid)))!;
      await open(t, id, existing: existing);
      expect(find.byKey(const ValueKey('consentCore')), findsNothing);
      await pickDob(t);
      await t.ensureVisible(find.byKey(const ValueKey('detailsContinue')));
      await t.tap(find.byKey(const ValueKey('detailsContinue')));
      await settle(t);
      expect((await t.runAsync(() => db.patientById(pid)))!['setup_stage'], 5);
    });
  });

  group('the whole app', () {
    Future<void> boot(WidgetTester t, String accountId, {bool asked = true}) async {
      if (asked) await t.runAsync(() => db.setPermissionsAsked(accountId));
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: Root(
              db: db, notifier: _Noop(db), voice: Voice(), otp: DevOtpService(),
              permissions: asker, session: _Session(accountId))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a new account: permissions once, then personal details, then the dashboard', (t) async {
      final id = await newAccount(t);
      await boot(t, id, asked: false);
      expect(find.byKey(const ValueKey('permissionsScreen')), findsOneWidget);
      expect(asker.calls, 0); // opening the app asked for nothing
      await t.tap(find.byKey(const ValueKey('allowPermissions')));
      await settle(t);
      await settle(t);
      expect(asker.calls, 1);
      expect(find.byKey(const ValueKey('permissionsScreen')), findsNothing);
      expect(find.byKey(const ValueKey('personalDetails')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await pickDob(t);
      await t.ensureVisible(find.byKey(const ValueKey('consentCore')));
      await t.tap(find.byKey(const ValueKey('consentCore')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('detailsContinue')));
      await t.tap(find.byKey(const ValueKey('detailsContinue')));
      await settle(t);
      await settle(t);
      expect(find.byType(NavigationBar), findsOneWidget); // the dashboard, with no Complete-profile steps
      expect(find.text('Family members'), findsNothing);
    });

    testWidgets('a profile started on an older version, with a birth date, simply opens the dashboard', (t) async {
      final id = await newAccount(t);
      final pid = (await t.runAsync(() => db.createPatient(
          accountId: id, phone: '+919876543210', displayName: 'Asha Devi',
          baselineLevel: 2, language: 'en', createdBy: 'x')))!;
      await t.runAsync(() => db.updateProfileBasics(patientId: pid, dob: DateTime(1950, 3, 2), by: 'x'));
      await t.runAsync(() => db.setSetupStage(pid, 2)); // stopped half way
      await boot(t, id);
      for (var i = 0; i < 4; i++) {
        await settle(t);
      }
      expect(find.byType(NavigationBar), findsOneWidget);
      expect((await t.runAsync(() => db.patientById(pid)))!['setup_stage'], 5);
    });
  });

  group('permissions', () {
    testWidgets('Not now asks nothing and the screen never comes back', (t) async {
      final id = await newAccount(t);
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: Root(
              db: db, notifier: _Noop(db), voice: Voice(), otp: DevOtpService(),
              permissions: asker, session: _Session(id))));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('permissionsNotNow')));
      await settle(t);
      await settle(t);
      expect(asker.calls, 0);
      expect(await t.runAsync(() => db.permissionsAsked(id)), isTrue);
      expect(find.byKey(const ValueKey('permissionsScreen')), findsNothing);
      // a restart goes on to the next step, not back to the permissions
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(
          home: Root(
              db: db, notifier: _Noop(db), voice: Voice(), otp: DevOtpService(),
              permissions: asker, session: _Session(id))));
      await settle(t);
      await settle(t);
      expect(find.byKey(const ValueKey('permissionsScreen')), findsNothing);
      expect(find.byKey(const ValueKey('personalDetails')), findsOneWidget);
    });

    testWidgets('it lists exactly what is needed: alerts, exact alarms, microphone, location', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: PermissionsScreen(
              lang: 'en', asker: asker, notifier: _Noop(db), onDone: () {})));
      for (final x in ['Alerts and notifications', 'Reminders on time', 'Microphone', 'Location']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
      expect(find.textContaining('no other permission is needed'), findsOneWidget);
    });

    test('accounts that existed before this version are not asked again', () async {
      final old = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await old.execute('CREATE TABLE accounts(id TEXT PRIMARY KEY, phone TEXT, role TEXT, name TEXT, server_user_id TEXT, created_at TEXT)');
      await old.insert('accounts', {'id': 'a', 'phone': '1', 'role': 'patient', 'name': 'Old', 'created_at': 'x'});
      await AppDatabase.upgradeSchema(old, 13);
      expect((await old.query('accounts')).single['permissions_asked'], 1);
      await old.close();
    });
  });
}
