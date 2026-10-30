// Renders the main screens on a small phone, a normal phone and a tablet, with
// normal and very large system text, in all four languages' longest case
// (Hindi/Bengali), and fails on any overflow or layout exception.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/features/remote/remote_home.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/features/reminders/reminders_screen.dart';
import 'package:smriti_assist/core/languages.dart';
import 'package:smriti_assist/core/responsive.dart';
import 'package:smriti_assist/core/theme.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/data/session_store.dart';
import 'package:smriti_assist/features/auth/auth_screen.dart';
import 'package:smriti_assist/features/onboarding/onboarding_screen.dart';
import 'package:smriti_assist/features/profile/profile_flow.dart';
import 'package:smriti_assist/features/auth/welcome_screen.dart';
import 'package:smriti_assist/features/companion/chat_screen.dart';
import 'package:smriti_assist/features/games/attention_game.dart';
import 'package:smriti_assist/features/games/memory_match_game.dart';
import 'package:smriti_assist/features/games/number_order_game.dart';
import 'package:smriti_assist/features/games/puzzle_fix_game.dart';
import 'package:smriti_assist/features/games/routine_game.dart';
import 'package:smriti_assist/features/games/word_recall_game.dart';
import 'package:smriti_assist/features/onboarding/restore_screen.dart';
import 'package:smriti_assist/features/shell/games_tab.dart';
import 'package:smriti_assist/features/shell/home_tab.dart';
import 'package:smriti_assist/features/shell/profile_tab.dart';
import 'package:smriti_assist/features/shell/progress_screen.dart';
import 'package:smriti_assist/services/companion_service.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/reminder_notifier.dart';
import 'package:smriti_assist/services/voice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Env {
  const _Env(this.name, this.size, this.systemScale);
  final String name;
  final Size size;
  final double systemScale;
}

const _envs = [
  _Env('small phone', Size(320, 568), 1.0),
  _Env('small phone, large text', Size(320, 568), 1.6),
  _Env('normal phone', Size(390, 844), 1.0),
  _Env('normal phone, large text', Size(390, 844), 1.6),
  _Env('tablet', Size(800, 1280), 1.0),
];

void main() {
  late AppDatabase db;
  late String pid;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final fam in {
      'Nunito': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'Lexend': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'NotoSansBengali': ['Regular', 'SemiBold', 'Bold'],
      'NotoSansDevanagari': ['Regular', 'SemiBold', 'Bold'],
    }.entries) {
      final font = FontLoader(fam.key);
      for (final w in fam.value) {
        font.addFont(rootBundle.load('assets/fonts/${fam.key}-$w.ttf'));
      }
      await font.load();
    }
    sqfliteFfiInit();
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            singleInstance: false,
            version: AppDatabase.schemaVersion,
            onCreate: (d, _) => AppDatabase.createSchema(d)));
    db = AppDatabase.forTesting(raw);
    final a = await db.createAccount(phone: '+919876543210', role: 'patient', name: 'Dada');
    pid = await db.createPatient(
        accountId: a, phone: '+919876543210', displayName: 'Dada Ramchandra Prasad',
        baselineLevel: 2, language: 'en', createdBy: 'x');
    await db.recordConsent(
        patientId: pid,
        purposes: {'gameplay': true, 'reminders': true, 'family_contacts': true, 'caregiver_share': true},
        givenByName: 'Dada', givenByRelation: 'self', noticeVersion: 'v2');
    for (var i = 0; i < 6; i++) {
      await db.insertSession(
          patientId: pid, game: ['memory_match', 'attention', 'routine'][i % 3],
          startedAt: DateTime.now(), startLevel: 2, endLevel: 2, trials: 10, correct: 8);
    }
    await db.addReminder(patientId: pid, kind: ReminderKind.medicine, label: 'Tablet after breakfast',
        hour: 8, minute: 0, createdBy: 'x');
    await db.addReminder(patientId: pid, kind: ReminderKind.hydration, label: '', hour: 23, minute: 0, createdBy: 'x');
    await db.addFamilyMember(patientId: pid, name: 'Ravi Kumar', phone: '+919000000001', relation: 'son', by: 'x');
  });

  http.Response json(Object b) => http.Response(jsonEncode(b), 200,
      headers: {'content-type': 'application/json'});
  final api = ApiClient(
      baseUrl: 'https://api.example.com',
      tokens: MemoryTokenStore(),
      client: MockClient((r) async {
        final p = r.url.path;
        if (p == '/v1/invites') {
          return json([
            {'id': 'i', 'patient_display_name': 'Meera Devi', 'member_role': 'caretaker', 'created_at': 'x'}
          ]);
        }
        if (p == '/v1/my-patients') {
          return json([
            {'patient_id': 'p1', 'display_name': 'Asha Ramchandra Prasad', 'alerts_needing_attention': 2}
          ]);
        }
        return json({
          'patient': {'id': 'p1', 'display_name': 'Asha', 'baseline_level': 2},
          'range_days': 7, 'games_played': 14, 'streak': 3,
          'last_played': '2026-03-10T10:00:00',
          'daily': [0, 1, 0, 2, 1, 0, 3],
          'per_game': [
            {'game': 'memory_match', 'sessions': 4, 'accuracy': 0.75},
            {'game': 'word_recall', 'sessions': 3, 'accuracy': 0.7},
            {'game': 'puzzle_fix', 'sessions': 4, 'accuracy': 0.9},
            {'game': 'number_order', 'sessions': 3, 'accuracy': 0.64},
            {'game': 'attention', 'sessions': 4, 'accuracy': 0.76},
            {'game': 'routine', 'sessions': 2, 'accuracy': 0.5}
          ],
          'adherence': {'expected': 6, 'done': 3},
          'alerts': [{'kind': 'inactive', 'severity': 'attention', 'a': 3, 'b': 0}],
        });
      }));

  final screens = <String, Widget Function(String lang)>{
    'memory game': (l) => MemoryMatchGame(db: db, patientId: pid, baselineLevel: 3, startLevel: 3, language: l, voice: Voice(), voiceOn: false),
    'attention game': (l) => AttentionGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5, language: l, voice: Voice(), voiceOn: false),
    'routine game': (l) => RoutineGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5, language: l, voice: Voice(), voiceOn: false),
    'word recall game': (l) => WordRecallGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5, language: l, voice: Voice(), voiceOn: false),
    'puzzle game': (l) => PuzzleFixGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5, language: l, voice: Voice(), voiceOn: false),
    'number game': (l) => NumberOrderGame(db: db, patientId: pid, baselineLevel: 5, startLevel: 5, language: l, voice: Voice(), voiceOn: false),
    'reminders (water tab data in the db)': (l) => RemindersScreen(
        db: db, notifier: ReminderNotifier(db), patientId: pid, language: l, embedded: true),
    'remote home': (l) => RemoteHome(
        api: api, user: const ServerUser('u', 'caretaker', 'Ravi Kumar Sharma'),
        lang: l, onLogout: () {}),
    'remote report': (l) => RemoteReportScreen(
        api: api, patientId: 'p1', name: 'Asha Ramchandra Prasad', lang: l),
    'remote patient': (l) => RemotePatientScreen(
        api: api, patientId: 'p1', name: 'Asha Ramchandra Prasad', lang: l, canSetBaseline: true),
    'allow permissions': (l) => OnboardingScreen(
        db: db, account: const {'id': 'a1', 'phone': '9999999999', 'name': 'Asha Ramchandra Prasad'},
        lang: l, onDone: () {}),
    'welcome': (l) => WelcomeScreen(lang: l, onGetStarted: () {}, onLogin: () {}),
    'auth': (l) => AuthScreen(
        db: db, otp: DevOtpService(), session: const SessionStore(), lang: l,
        onLangChanged: (_) {}, onLoggedIn: () {}, initialSignUp: true, onBack: () {}),
    'profile about you': (l) => ProfileFlow(
        db: db, notifier: ReminderNotifier(db), onDone: () {},
        patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'phone': '+919876543210', 'email': null, 'city': null, 'state': null, 'language': l, 'dob': '1948-03-02', 'photo': null, 'setup_stage': 0}),
    'profile family': (l) => ProfileFlow(
        db: db, notifier: ReminderNotifier(db), onDone: () {},
        patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'phone': '+919876543210', 'email': null, 'city': null, 'state': null, 'language': l, 'dob': '1948-03-02', 'photo': null, 'setup_stage': 1}),
    'profile doctor': (l) => ProfileFlow(
        db: db, notifier: ReminderNotifier(db), onDone: () {},
        patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'phone': '+919876543210', 'email': null, 'city': null, 'state': null, 'language': l, 'dob': '1948-03-02', 'photo': null, 'setup_stage': 2}),
    'profile caregiver': (l) => ProfileFlow(
        db: db, notifier: ReminderNotifier(db), onDone: () {},
        patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'phone': '+919876543210', 'email': null, 'city': null, 'state': null, 'language': l, 'dob': '1948-03-02', 'photo': null, 'setup_stage': 3}),
    'profile routine': (l) => ProfileFlow(
        db: db, notifier: ReminderNotifier(db), onDone: () {},
        patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'phone': '+919876543210', 'email': null, 'city': null, 'state': null, 'language': l, 'dob': '1948-03-02', 'photo': null, 'setup_stage': 4}),
    'home': (l) => Scaffold(
        body: SafeArea(
            child: HomeTab(
                db: db, patientId: pid, name: 'Dada Ramchandra Prasad', photo: null, lang: l,
                onPlay: () {}, onGames: () {}, onReminders: () {}, onProgress: () {}, onTalk: () {},
                onChatCaregiver: () {}, onChatDoctor: () {}, unreadCaregiver: 3, unreadDoctor: 12))),
    'games': (l) => Scaffold(
        body: SafeArea(
            child: GamesTab(lang: l, onPlay: (_) {}))),
    'progress': (l) => ProgressScreen(db: db, patientId: pid, lang: l),
    'profile': (l) => Scaffold(
        body: SafeArea(
            child: ProfileTab(
                db: db, notifier: ReminderNotifier(db),
                patient: {'id': pid, 'display_name': 'Dada Ramchandra Prasad', 'language': l,
                  'phone': '+919876543210', 'dob': '1948-03-02', 'voice_enabled': 1, 'photo': null},
                onChanged: () {}, onLogout: () {}))),
    'chat': (l) => ChatScreen(
        service: CompanionService(db: db), voice: Voice(), db: db, patientId: pid,
        name: 'Dada Ramchandra Prasad', lang: l, voiceEnabled: false),
    'restore': (l) => RestoreScreen(
        name: 'Dada Ramchandra Prasad', lang: l, onRestore: () async => true, onStartFresh: () {}),
  };

  // Scripts and lengths that stress layouts: Devanagari, Bengali, long Tamil and
  // Malayalam words, right-to-left Urdu, and the Ol Chiki script of Santali.
  for (final lang in ['en', 'hi', 'bn', 'ta', 'ml', 'ur', 'sat']) {
    for (final entry in screens.entries) {
      for (final env in _envs) {
        testWidgets('${entry.key} / $lang / ${env.name}', (t) async {
          await t.binding.setSurfaceSize(env.size);
          t.platformDispatcher.textScaleFactorTestValue = env.systemScale;
          addTearDown(() {
            t.platformDispatcher.clearTextScaleFactorTestValue();
            t.binding.setSurfaceSize(null);
          });
          final problems = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (d) {
            problems.add(d.toString());
            previous?.call(d);
          };
          addTearDown(() => FlutterError.onError = previous);
          await t.pumpWidget(MaterialApp(
            theme: buildTheme(),
            debugShowCheckedModeBanner: false,
            builder: (c, child) => Directionality(
                textDirection: isRtl(lang) ? TextDirection.rtl : TextDirection.ltr,
                child: ResponsiveScope(child: child!)),
            home: entry.value(lang),
          ));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await t.pump(const Duration(milliseconds: 300));
          final thrown = t.takeException();
          // Take the screen down so its timers stop before the test ends.
          await t.pumpWidget(const SizedBox());
          expect(thrown, isNull, reason: problems.join('\n---\n'));
        });
      }
    }
  }

  test('font scale follows the screen and respects the system setting', () {
    expect(fontScaleFor(390, 1.0), closeTo(kTextBase, 0.001)); // compact base
    expect(fontScaleFor(800, 1.0), closeTo(kTextBase * 1.3, 0.001)); // tablet grows, capped
    expect(fontScaleFor(320, 1.0), closeTo(kTextBase * 0.9, 0.001)); // narrow shrinks a little
    expect(fontScaleFor(390, 1.5), closeTo(kTextBase * 1.5, 0.001)); // person's own setting kept
    expect(fontScaleFor(800, 3.0), lessThanOrEqualTo(1.9)); // never runaway
    expect(fontScaleFor(390, 0.5), greaterThanOrEqualTo(0.7));
  });
}
