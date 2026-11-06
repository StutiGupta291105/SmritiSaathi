import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/data/session_store.dart';
import 'package:smriti_assist/features/auth/auth_screen.dart';
import 'package:smriti_assist/features/auth/garden_frame.dart';
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

class _Noop extends ReminderNotifier {
  _Noop(super.db);
  @override
  Future<void> resync({required String patientId, required String lang}) async {}
}

void main() {
  late Database raw;
  late AppDatabase db;

  setUp(() async {
    sqfliteFfiInit();
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
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
    testWidgets('the welcome screen is the garden with Create account and Log in', (t) async {
      var made = false, login = false;
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: WelcomeScreen(
              lang: 'en', onGetStarted: () => made = true, onLogin: () => login = true)));
      expect(find.byKey(const ValueKey('authGarden')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('getStarted')));
      await t.tap(find.byKey(const ValueKey('welcomeLogin')));
      expect([made, login], [true, true]);
    });

    testWidgets('creating a patient account shows three steps; caregiver and login two', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      Widget auth(bool signUp) => MaterialApp(
          home: AuthScreen(
              db: db, otp: DevOtpService(), session: _Session(), lang: 'en',
              onLangChanged: (_) {}, onLoggedIn: () {}, initialSignUp: signUp));
      await t.pumpWidget(auth(true));
      expect(find.byType(StepTimeline), findsOneWidget);
      expect(find.text('Your number'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('About you'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('role_caretaker')));
      await t.pump();
      expect(find.text('About you'), findsNothing); // a caregiver goes straight to their home
      await t.pumpWidget(auth(false));
      expect(find.text('About you'), findsNothing);
      expect(find.text('Your number'), findsOneWidget);
    });

    testWidgets('the timeline moves to the code step after the number is sent', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1300));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: AuthScreen(
              db: db, otp: DevOtpService(), session: _Session(), lang: 'en',
              onLangChanged: (_) {}, onLoggedIn: () {}, initialSignUp: true)));
      await t.enterText(find.byType(TextField).at(0), 'Asha Devi');
      await t.enterText(find.byType(TextField).at(1), '+919876543210');
      await t.ensureVisible(find.byKey(const ValueKey('authSubmit')));
      await t.tap(find.byKey(const ValueKey('authSubmit')));
      for (var i = 0; i < 3; i++) {
        await settle(t);
      }
      expect(find.byKey(const ValueKey('step1')), findsOneWidget);
      expect(find.textContaining('+91'), findsWidgets);
      expect(t.widget<StepTimeline>(find.byType(StepTimeline)).current, 1);
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
      expect(t.widget<StepTimeline>(find.byType(StepTimeline)).current, 2);
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
    Future<void> boot(WidgetTester t, String accountId) async {
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: Root(
              db: db, notifier: _Noop(db), voice: Voice(), otp: DevOtpService(),
              session: _Session(accountId))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a new patient account goes from the code to personal details, then the dashboard', (t) async {
      final id = await newAccount(t);
      await boot(t, id);
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
}
