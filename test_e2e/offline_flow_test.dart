// ignore_for_file: invalid_use_of_visible_for_testing_member
// End-to-end test of OFFLINE-FIRST behaviour against a RUNNING server: the real app
// code, a real database file, and a network that is switched off and on.
//
// Not part of `flutter test` (it needs a server). Start one with a fixed login code:
//   SMRITI_SMS_PROVIDER=test SMRITI_REQUESTS_PER_MINUTE_IP=100000 \
//   SMRITI_OTP_PER_HOUR_IP=1000 SMRITI_OTP_PER_HOUR_PHONE=1000 \
//   uvicorn app.main:create_app --factory --port 8765
// and run:  E2E_URL=http://127.0.0.1:8765 flutter test test_e2e/offline_flow_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final url = Platform.environment['E2E_URL'];

/// The network: pass calls through, or fail like a phone with no signal.
class Switch extends http.BaseClient {
  Switch(this.inner);
  final http.Client inner;
  bool up = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!up) throw http.ClientException('no signal');
    return inner.send(request);
  }
}

class Phone {
  Phone(this.net, this.db, this.api);
  final Switch net;
  AppDatabase db;
  ApiClient api;
}

Future<AppDatabase> openDb(String path) async {
  sqfliteFfiInit();
  final raw = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(
          singleInstance: false,
          version: AppDatabase.schemaVersion,
          onCreate: (d, _) => AppDatabase.createSchema(d)));
  return AppDatabase.forTesting(raw);
}

Phone newPhone(String path, AppDatabase db) {
  final net = Switch(http.Client());
  return Phone(net, db, ApiClient(baseUrl: url!, tokens: MemoryTokenStore(), client: net, store: db));
}

Future<ServerUser> signIn(ApiClient api, String phone, String role, {required String name}) async {
  final otp = ApiOtpService(api);
  expect(await otp.send(phone, role: role, signUp: true), OtpResult.ok);
  expect(await otp.verify(phone, DevOtpService.testCode, role: role, signUp: true, name: name), OtpResult.ok);
  return otp.serverUser!;
}

void main() {
  final skip = url == null ? 'set E2E_URL' : null;
  final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
  final patientPhone = '+9198${stamp.toString().padLeft(8, '0')}';
  final carerPhone = '+9197${stamp.toString().padLeft(8, '0')}';

  test('a patient lives offline for a while, and nothing is lost or doubled when the network returns', () async {
    final dir = Directory.systemTemp.createTempSync('smriti_offline_');
    final path = '${dir.path}/phone.db'; // a real file, so the phone can "restart"
    final patientTokens = MemoryTokenStore(); // the app keeps its session in the secure store
    final net0 = Switch(http.Client());
    final db0 = await openDb(path);
    var p = Phone(net0, db0, ApiClient(baseUrl: url!, tokens: patientTokens, client: net0, store: db0));
    final pUser = await signIn(p.api, patientPhone, 'patient', name: 'Asha Devi');
    final acc = await p.db.createAccount(phone: patientPhone, role: 'patient', name: 'Asha Devi');
    await p.db.linkServerAccount(acc, pUser.id);
    final pid = await p.db.createPatient(accountId: acc, phone: patientPhone, displayName: 'Asha Devi',
        baselineLevel: 2, language: 'en', createdBy: 'Asha');
    await p.db.recordConsent(patientId: pid, purposes: createdOnly(), givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');

    // the caregiver (separate phone, online all along)
    final c = newPhone('${dir.path}/carer.db', await openDb('${dir.path}/carer.db'));
    final cUser = await signIn(c.api, carerPhone, 'caretaker', name: 'Ravi');

    // 1. ONLINE: invite by Care ID, accept, chat thread exists
    await p.db.addCareInvite(patientId: pid, kind: 'caregiver', name: 'Ravi', professionalId: cUser.careId!, by: 'Asha');
    expect(await SyncService(p.db, p.api).run(pid), SyncOutcome.done);
    final inv = await c.api.myInvites();
    await c.api.acceptInvite(inv.single['id'] as String);
    await SyncService(p.db, p.api).run(pid);
    final serverId = (await p.db.patientById(pid))!['server_patient_id'] as String;
    final link = (await p.api.chatThreads()).single['link_id'] as String;
    await c.api.chatMessages(link);
    expect((await c.api.myPatients()).single['patient_id'], serverId); // caregiver sees them (and the phone saves that)

    // 2. OFFLINE: the whole app still works
    p.net.up = false;
    for (var i = 0; i < 3; i++) {
      await p.db.insertSession(patientId: pid, game: 'attention', startedAt: DateTime.now(),
          startLevel: 2, endLevel: 2, trials: 10, correct: 7 + (i % 2));
    }
    await p.db.addReminder(patientId: pid, kind: ReminderKind.medicine, label: 'Tablet', hour: 9, minute: 0, createdBy: 'Asha');
    await p.db.addWater(pid);
    await p.db.addWater(pid);
    await p.api.queueChatMessage(link, kind: 'text', text: 'I fell asleep, call me');
    await p.api.queueChatMessage(link, kind: 'text', text: 'Second message');
    expect(await SyncService(p.db, p.api).run(pid), SyncOutcome.offline); // tries, fails quietly
    expect((await p.db.unsyncedSessions(pid)).length, 3);
    expect(await p.db.pendingSyncCount(pid), greaterThanOrEqualTo(5));
    expect(await p.db.waterToday(pid), 2);
    expect((await p.db.listReminders(pid)).length, 1);
    // while the patient was offline the caregiver wrote too; the patient cannot see it yet
    await c.api.sendChatMessage(link, kind: 'text', text: 'Did you take your tablet?');

    // 3. THE APP IS CLOSED AND REOPENED while still offline: nothing queued is lost
    await p.db.close();
    final reopened = await openDb(path);
    p = Phone(p.net, reopened,
        ApiClient(baseUrl: url!, tokens: patientTokens, client: p.net, store: reopened));
    expect((await p.db.outboxList()).length, 2);
    expect((await p.db.unsyncedSessions(pid)).length, 3);
    expect(await p.db.waterToday(pid), 2);

    // 4. ONLINE again: everything goes out exactly once
    p.net.up = true;
    expect(await SyncService(p.db, p.api).run(pid), SyncOutcome.done);
    await p.api.flushOutbox();
    expect(await p.db.unsyncedSessions(pid), isEmpty);
    expect(await p.db.outboxList(), isEmpty);
    expect(await p.db.pendingSyncCount(pid), 0);
    final seen = await c.api.chatMessages(link);
    final texts = [for (final m in seen) m['text']];
    expect(texts.where((t) => t == 'I fell asleep, call me').length, 1, reason: 'delivered exactly once');
    expect(texts.where((t) => t == 'Second message').length, 1);
    expect(texts.indexOf('I fell asleep, call me') < texts.indexOf('Second message'), isTrue, reason: 'in order');
    expect((await c.api.report(serverId, 7))['games_played'], 3);
    // the patient now receives what the caregiver wrote meanwhile
    expect([for (final m in await p.api.chatMessages(link)) m['text']], contains('Did you take your tablet?'));
    // a second run sends nothing again
    await SyncService(p.db, p.api).run(pid);
    expect((await c.api.report(serverId, 7))['games_played'], 3);
    expect([for (final m in await c.api.chatMessages(link)) m['text']].where((t) => t == 'Second message').length, 1);

    // 5. THE CAREGIVER LOSES SIGNAL: the last dashboard is still there, marked as saved
    expect(c.api.staleSince.value, isNull);
    c.net.up = false;
    expect((await c.api.myPatients()).single['patient_id'], serverId);
    expect((await c.api.report(serverId, 7))['games_played'], 3);
    expect(c.api.staleSince.value, isNotNull);
    // ...and a reply written offline waits, then goes out
    await c.api.queueChatMessage(link, kind: 'text', text: 'Reply from a train');
    expect(c.api.outboxCount.value, 1);
    c.net.up = true;
    await c.api.myPatients();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.api.outboxCount.value, 0);
    expect(c.api.staleSince.value, isNull);
    expect([for (final m in await p.api.chatMessages(link)) m['text']], contains('Reply from a train'));

    // 6. LOG OUT wipes what was saved for the next person on the phone
    await c.api.logout();
    expect(await c.db.cacheGet('/v1/my-patients'), isNull);
    dir.deleteSync(recursive: true);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}

/// All the purposes the scenario needs.
Map<String, bool> createdOnly() => {
      'gameplay': true,
      'reminders': true,
      'sync': true,
      'caregiver_share': true,
    };
