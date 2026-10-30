import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/core/companion_offline.dart';
import 'package:smriti_assist/core/safety_data.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/companion_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _phone = '+919876543210';

Reminder _r(String id, ReminderKind k, int h, int m, {bool active = true}) =>
    Reminder(id: id, kind: k, label: 'SECRET LABEL', hour: h, minute: m, active: active);

void main() {
  group('on-device helper', () {
    final now = DateTime(2026, 3, 10, 10, 30); // a Tuesday

    test('says the day and time in each language', () {
      expect(dayAnswer('en', now), 'Today is Tuesday, 10 March 2026. The time is 10:30.');
      expect(dayAnswer('hi', now), contains('मंगलवार'));
      expect(dayAnswer('bn', now), contains('মঙ্গলবার'));
      expect(dayAnswer('as', now), contains('মঙলবাৰ'));
      expect(dayAnswer('xx', now), startsWith('Today is'));
    });

    test('next reminder skips past, done and inactive ones', () {
      final rs = [
        _r('a', ReminderKind.medicine, 8, 0), // already past
        _r('b', ReminderKind.hydration, 11, 0), // done
        _r('c', ReminderKind.activity, 12, 30),
        _r('d', ReminderKind.medicine, 12, 0, active: false),
      ];
      final done = {'b|2026-03-10'};
      expect(nextAnswer('en', rs, done, now), 'Next is Activity at 12:30.');
      expect(nextAnswer('en', rs.take(1).toList(), {}, now),
          'Nothing more is planned for today.');
      expect(nextAnswer('en', rs, done, now), isNot(contains('SECRET')));
    });

    test('kind thoughts exist in every language and vary', () {
      for (final l in ['en', 'hi', 'bn', 'as']) {
        expect({for (var i = 0; i < 3; i++) niceThing(l, i)}.length, 3);
      }
    });

    test('emergency words are caught in the right language and in English', () {
      expect(isEmergencyText('I have chest pain', 'en'), isTrue);
      expect(isEmergencyText('मेरे सीने में दर्द है', 'hi'), isTrue);
      expect(isEmergencyText('আমার বুকে ব্যথা', 'bn'), isTrue);
      expect(isEmergencyText('মই পৰি গৈছো', 'as'), isTrue);
      expect(isEmergencyText('i fell down', 'hi'), isTrue);
      expect(isEmergencyText('Tell me about Diwali', 'en'), isFalse);
      // written in another language than the app is set to
      expect(isEmergencyText('मेरे सीने में दर्द है', 'en'), isTrue);
      expect(emergencyTextFor('মই পৰি গৈছো', 'en'), emergencyText('as'));
      expect(emergencyTextFor('i fell down', 'hi'), emergencyText('hi'));
      expect(emergencyText('en'), contains('112'));
      for (final l in ['en', 'hi', 'bn', 'as']) {
        expect(emergencyReply[l], isNotEmpty);
        expect(emergencyWords[l], isNotEmpty);
      }
    });
  });

  group('service', () {
    late AppDatabase db;
    late Database raw;
    late String pid;
    late List<String> calls;
    Map<String, dynamic>? sentBody;
    var failWith = 0;
    var offline = false;

    CompanionService make({bool withApi = true, DateTime? at}) => CompanionService(
          db: db,
          clock: () => at ?? DateTime(2026, 3, 10, 10, 30),
          api: withApi
              ? ApiClient(
                  baseUrl: 'https://api.example.com',
                  tokens: MemoryTokenStore()
                    ..data.addAll({'api_access': 'A', 'api_refresh': 'R'}),
                  client: MockClient((r) async {
                    if (offline) throw http.ClientException('x');
                    calls.add(r.url.path);
                    sentBody = jsonDecode(r.body) as Map<String, dynamic>;
                    if (failWith != 0) {
                      return http.Response(jsonEncode({'detail': 'x'}), failWith,
                          headers: {'content-type': 'application/json'});
                    }
                    return http.Response(jsonEncode({'reply': 'I am here.', 'emergency': false}), 200,
                        headers: {'content-type': 'application/json'});
                  }))
              : null,
        );

    Future<void> consent(bool on) => on
        ? db.recordConsent(
            patientId: pid,
            purposes: {'companion': true},
            givenByName: 'Asha',
            givenByRelation: 'self',
            noticeVersion: 'v2')
        : db.withdrawConsent(
            patientId: pid,
            purpose: 'companion',
            byName: 'Asha',
            byRelation: 'self',
            noticeVersion: 'v2');

    setUp(() async {
      sqfliteFfiInit();
      raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              singleInstance: false,
              version: AppDatabase.schemaVersion,
              onCreate: (d, _) => AppDatabase.createSchema(d)));
      db = AppDatabase.forTesting(raw);
      final acc = await db.createAccount(phone: _phone, role: 'patient', name: 'Asha');
      pid = await db.createPatient(
          accountId: acc,
          phone: _phone,
          displayName: 'Asha',
          baselineLevel: 2,
          language: 'en',
          createdBy: 'Asha');
      await db.recordConsent(
          patientId: pid,
          purposes: {'gameplay': true, 'reminders': true},
          givenByName: 'Asha',
          givenByRelation: 'self',
          noticeVersion: 'v2');
      await db.setServerPatientId(pid, 'srv-1');
      calls = [];
      sentBody = null;
      failWith = 0;
      offline = false;
    });

    tearDown(() => raw.close());

    Future<CompanionReply> ask(CompanionService s, String text) => s.ask(
        patientId: pid, lang: 'en', firstName: 'Asha', history: const [], text: text);

    test('without the companion consent nothing goes online', () async {
      final r = await ask(make(), 'How are you?');
      expect(calls, isEmpty);
      expect(r.text, contains('Tap a button'));
    });

    test('before the first sync (no server id) it stays on the phone', () async {
      await consent(true);
      await raw.update('patients', {'server_patient_id': null});
      final r = await ask(make(), 'Hello');
      expect(calls, isEmpty);
      expect(r.text, contains('Tap a button'));
    });

    test('without an API address the helper stays on the phone', () async {
      await consent(true);
      final r = await ask(make(withApi: false), 'Hello');
      expect(calls, isEmpty);
      expect(r.offline, isFalse);
    });

    test('with consent a message goes to the server with facts but no reminder text',
        () async {
      await consent(true);
      await db.addReminder(
          patientId: pid,
          kind: ReminderKind.medicine,
          label: 'SECRET LABEL',
          hour: 12,
          minute: 0,
          createdBy: 'Asha');
      final r = await make().ask(
          patientId: pid,
          lang: 'en',
          firstName: 'Asha',
          history: const [ChatTurn(false, 'Hi'), ChatTurn(true, 'Hello')],
          text: 'Tell me a story');
      expect(r.text, 'I am here.');
      expect(calls, ['/v1/patients/srv-1/companion/chat']);
      final body = sentBody!;
      expect(jsonEncode(body), isNot(contains('SECRET')));
      expect((body['messages'] as List).map((m) => m['role']), ['assistant', 'user', 'user']);
      expect(body['today'], [
        {'kind': 'medicine', 'time': '12:00', 'done': false}
      ]);
      expect(body['now_text'], contains('Tuesday'));
    });

    test('emergencies are answered on the phone and never sent', () async {
      await consent(true);
      final r = await ask(make(), 'I have chest pain');
      expect(r.emergency, isTrue);
      expect(r.text, contains('112'));
      expect(calls, isEmpty);
    });

    test('each failure says what is wrong; no internet falls back to the helper', () async {
      await consent(true);
      failWith = 429;
      expect((await ask(make(), 'Hello')).text, contains('enough questions for today'));
      failWith = 503;
      final off = await ask(make(), 'Hello');
      expect(off.text, contains('not switched on'));
      expect(off.offline, isFalse); // the phone is online; the service has no AI yet
      failWith = 401;
      expect((await ask(make(), 'Hello')).text, contains('sign in again'));
      failWith = 0;
      offline = true;
      final r = await ask(make(), 'Hello');
      expect(r.offline, isTrue);
      expect(r.text, contains('Tap a button'));
    });

    test('withdrawing the consent stops online chat at once', () async {
      await consent(true);
      expect((await ask(make(), 'Hello')).text, 'I am here.');
      await consent(false);
      calls.clear();
      expect((await ask(make(), 'Hello')).text, contains('Tap a button'));
      expect(calls, isEmpty);
    });

    test('quick answers work with no network at all', () async {
      final s = make(withApi: false);
      expect((await s.day('en')).text, contains('Tuesday'));
      expect((await s.next(pid, 'en')).text, 'Nothing more is planned for today.');
      expect(s.nice('en').text, isNotEmpty);
      expect(await s.onlinePossible(), isFalse);
    });
  });
}
