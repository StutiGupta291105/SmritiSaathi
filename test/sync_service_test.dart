import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _phone = '+919876543210';

http.Response _j(int s, Object b) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

void main() {
  late AppDatabase db;
  late Database raw;
  late String pid;
  late List<String> calls;
  late Map<String, Object?> lastSync;
  late Object? lastConsents;
  var offline = false;
  var existing = false;
  var serverBaseline = 2;

  SyncService make({int linkStatus = 200}) => SyncService(
      db,
      ApiClient(
          baseUrl: 'https://api.example.com',
          tokens: MemoryTokenStore(),
          client: MockClient((r) async {
            if (offline) throw http.ClientException('offline');
            calls.add('${r.method} ${r.url.path}');
            final body = r.body.isEmpty ? null : jsonDecode(r.body);
            final p = r.url.path;
            if (p == '/v1/patients' && existing) return _j(409, {'detail': 'patient_exists'});
            if (p == '/v1/patients/me') return _j(200, {'id': 'srv-old', 'baseline_level': serverBaseline});
            if (p.endsWith('/baseline')) {
              serverBaseline = body['baseline_level'] as int;
              return _j(200, {'id': 'srv-p', 'baseline_level': serverBaseline});
            }
            if (p == '/v1/patients') return _j(201, {'id': 'srv-p', 'baseline_level': serverBaseline});
            if (p.endsWith('/consents')) {
              lastConsents = body;
              return _j(200, {});
            }
            if (p.endsWith('/invites')) {
              expect(body['role'], 'caretaker'); // local 'caregiver' maps here
              return _j(201, {'id': 'srv-l'});
            }
            if (p.endsWith('/sync')) {
              lastSync = body;
              return _j(200, {'sessions': 1, 'schedules': 1, 'marks': 0});
            }
            if (p.endsWith('/links')) {
              return _j(linkStatus, [
                {'id': 'srv-l', 'status': 'accepted', 'verified': true}
              ]);
            }
            return _j(404, {'detail': 'x'});
          })));

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
        purposes: {
          'gameplay': true,
          'reminders': true,
          'caregiver_share': true,
          'sync': true
        },
        givenByName: 'Asha',
        givenByRelation: 'self',
        noticeVersion: 'v2');
    calls = [];
    offline = false;
    existing = false;
    serverBaseline = 2;
  });

  tearDown(() => raw.close());

  test('first run sends everything in order and marks it synced', () async {
    await db.insertSession(
        patientId: pid,
        game: 'memory_match',
        startedAt: DateTime.now(),
        startLevel: 2,
        endLevel: 2,
        trials: 3,
        correct: 3);
    await db.addReminder(
        patientId: pid,
        kind: ReminderKind.medicine,
        label: 'Tablet',
        hour: 9,
        minute: 0,
        createdBy: 'Asha');
    final link = await db.addCareInvite(
        patientId: pid,
        kind: 'caregiver',
        name: 'Ravi',
        professionalId: '',
        phone: '+919811111111',
        by: 'Asha');

    expect(await make().run(pid), SyncOutcome.done);
    expect(calls, [
      'POST /v1/patients',
      'POST /v1/patients/srv-p/consents',
      'POST /v1/patients/srv-p/invites',
      'POST /v1/patients/srv-p/sync',
      'GET /v1/patients/me',
      'GET /v1/patients/srv-p/links',
    ]);
    expect((lastSync['sessions'] as List).length, 1);
    expect(jsonEncode(lastSync), isNot(contains('Tablet')));
    expect((lastConsents as Map)['consents'], isNotEmpty);
    expect(await db.unsyncedConsents(pid), isEmpty);
    expect(await db.unsyncedSessions(pid), isEmpty);
    final row = (await raw.query('care_links', where: 'id = ?', whereArgs: [link])).single;
    expect([row['server_link_id'], row['status'], row['verified']], ['srv-l', 'accepted', 1]);
  });

  test('second run does not recreate or resend consents and sessions', () async {
    await make().run(pid);
    calls.clear();
    await make().run(pid);
    expect(calls, ['GET /v1/patients/me', 'GET /v1/patients/srv-p/links']);
  });

  test('withdrawing sync stops uploads but still reports the withdrawal', () async {
    await make().run(pid);
    await db.withdrawConsent(
        patientId: pid,
        purpose: 'sync',
        byName: 'Asha',
        byRelation: 'self',
        noticeVersion: 'v2');
    await db.setReminderDone(
        patientId: pid,
        reminderId: 'r',
        day: DateTime.now(),
        done: true,
        by: 'Asha');
    calls.clear();
    await make().run(pid);
    expect(calls.any((c) => c.endsWith('/consents')), isTrue);
    expect(calls.any((c) => c.endsWith('/sync')), isFalse);
  });

  test('a patient that already exists on the server is adopted', () async {
    existing = true;
    expect(await make().run(pid), SyncOutcome.done);
    expect((await raw.query('patients')).single['server_patient_id'], 'srv-old');
    expect(calls.any((c) => c.contains('/srv-old/sync') || c.contains('/srv-old/consents')),
        isTrue);
  });

  test('a starting level changed online by a caretaker reaches this phone', () async {
    await make().run(pid);
    serverBaseline = 4; // caretaker changed it on the server
    await make().run(pid);
    expect((await db.patientById(pid))!['baseline_level'], 4);
    expect((await db.patientById(pid))!['server_baseline'], 4);
    expect(await db.verifyAuditChain(), isTrue);
  });

  test('a starting level changed on this phone is sent, and wins over an older server value',
      () async {
    await make().run(pid);
    await db.setBaseline(
        patientId: pid, newLevel: 5, caregiverName: 'Asha', reason: 'test');
    await make().run(pid);
    expect(serverBaseline, 5);
    expect((await db.patientById(pid))!['baseline_level'], 5);
    // both changed since the last sync: this phone wins, nothing flips back
    serverBaseline = 1;
    await db.setBaseline(
        patientId: pid, newLevel: 3, caregiverName: 'Asha', reason: 'test');
    await make().run(pid);
    expect(serverBaseline, 3);
    expect((await db.patientById(pid))!['baseline_level'], 3);
  });

  test('without the sync purpose the starting level is not exchanged', () async {
    await make().run(pid);
    await db.withdrawConsent(
        patientId: pid, purpose: 'sync', byName: 'Asha', byRelation: 'self', noticeVersion: 'v2');
    serverBaseline = 4;
    calls.clear();
    await make().run(pid);
    expect((await db.patientById(pid))!['baseline_level'], 2);
    expect(calls.contains('GET /v1/patients/me'), isFalse);
  });

  test('offline leaves everything queued', () async {
    offline = true;
    expect(await make().run(pid), SyncOutcome.offline);
    expect(await db.unsyncedConsents(pid), isNotEmpty);
    expect((await raw.query('patients')).single['server_patient_id'], isNull);
  });

  test('an expired login is reported', () async {
    final s = SyncService(
        db,
        ApiClient(
            baseUrl: 'https://api.example.com',
            tokens: MemoryTokenStore(),
            client: MockClient((r) async => _j(401, {'detail': 'invalid_token'}))));
    expect(await s.run(pid), SyncOutcome.signedOut);
  });
}
