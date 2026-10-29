// ignore_for_file: invalid_use_of_visible_for_testing_member
// End-to-end test of the app's real code against a RUNNING server (no mocks).
//
// Not part of `flutter test` (it needs a server). Run it with:
//   E2E_URL=http://127.0.0.1:8765 E2E_SMS_FILE=/path/to/sms.txt \
//     flutter test test_e2e/server_flow_test.dart
// where the server's SMS provider appends each message to E2E_SMS_FILE.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/companion_service.dart';
import 'package:smriti_assist/services/otp_service.dart';
import 'package:smriti_assist/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final url = Platform.environment['E2E_URL'];
final smsFile = Platform.environment['E2E_SMS_FILE'];

String lastCode() {
  final lines = File(smsFile!).readAsLinesSync();
  return RegExp(r'^(\d{6})').firstMatch(lines.last)!.group(1)!;
}

ApiClient newClient() =>
    ApiClient(baseUrl: url!, tokens: MemoryTokenStore());

Future<AppDatabase> newDb() async {
  sqfliteFfiInit();
  final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          singleInstance: false,
          version: AppDatabase.schemaVersion,
          onCreate: (d, _) => AppDatabase.createSchema(d)));
  return AppDatabase.forTesting(raw);
}

/// Real OTP login through ApiOtpService.
Future<ServerUser> signIn(ApiClient api, String phone, String role,
    {required bool signUp, String name = ''}) async {
  final otp = ApiOtpService(api);
  expect(await otp.send(phone, role: role, signUp: signUp), OtpResult.ok);
  expect(await otp.verify(phone, lastCode(), role: role, signUp: signUp, name: name),
      OtpResult.ok);
  return otp.serverUser!;
}

void main() {
  final skip = url == null || smsFile == null ? 'set E2E_URL and E2E_SMS_FILE' : null;
  final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
  final patientPhone = '+9198${stamp.toString().padLeft(8, '0')}';
  final carerPhone = '+9197${stamp.toString().padLeft(8, '0')}';

  test('patient -> sync -> caretaker -> companion -> restore -> erase', () async {
    final db = await newDb();
    final api = newClient();

    // 1. Patient signs up on the server and the phone.
    final user = await signIn(api, patientPhone, 'patient', signUp: true, name: 'Asha Devi');
    final acc = await db.createAccount(phone: patientPhone, role: 'patient', name: 'Asha Devi');
    await db.linkServerAccount(acc, user.id);
    final pid = await db.createPatient(
        accountId: acc, phone: patientPhone, displayName: 'Asha Devi',
        baselineLevel: 3, language: 'bn', createdBy: 'Asha');
    await db.recordConsent(
        patientId: pid,
        purposes: {
          'gameplay': true, 'reminders': true, 'sync': true,
          'caregiver_share': true, 'companion': true,
        },
        givenByName: 'Asha', givenByRelation: 'self', noticeVersion: 'v2');

    // 2. Play some games, add a reminder, invite a caretaker, sync.
    for (var i = 0; i < 3; i++) {
      await db.insertSession(
          patientId: pid, game: 'attention', startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
          startLevel: 3, endLevel: 3, trials: 10, correct: 8 - i);
    }
    await db.addReminder(
        patientId: pid, kind: ReminderKind.medicine, label: 'BP tablet SECRET',
        hour: 9, minute: 0, createdBy: 'Asha');
    await db.addCareInvite(
        patientId: pid, kind: 'caregiver', name: 'Ravi', professionalId: '',
        phone: carerPhone, by: 'Asha');
    expect(await SyncService(db, api).run(pid), SyncOutcome.done);
    expect(await db.unsyncedConsents(pid), isEmpty);
    expect(await db.unsyncedSessions(pid), isEmpty);
    expect(await SyncService(db, api).run(pid), SyncOutcome.done); // idempotent
    final serverId = (await db.patientById(pid))!['server_patient_id'] as String;

    // 3. Caretaker signs up, sees the invite, accepts, sees the report.
    final carer = newClient();
    await signIn(carer, carerPhone, 'caretaker', signUp: true, name: 'Ravi');
    final invites = await carer.myInvites();
    expect(invites.single['patient_display_name'], 'Asha Devi');
    await carer.acceptInvite(invites.single['id'] as String);
    final mine = await carer.myPatients();
    expect(mine.single['patient_id'], serverId);
    final report = await carer.report(serverId, 7);
    expect(report['games_played'], 3);
    expect(report.toString(), isNot(contains('SECRET'))); // reminder text never left
    await SyncService(db, api).run(pid); // patient's app sees 'accepted'
    expect((await db.listCareLinks(pid)).single['status'], 'accepted');
    await carer.setBaseline(serverId, 4);
    expect((await api.myPatient())['baseline_level'], 4);

    // 4. Talk to Smriti through the real server (dev provider).
    final talk = CompanionService(db: db, api: api);
    final reply = await talk.ask(
        patientId: pid, lang: 'bn', firstName: 'Asha', history: const [], text: 'Tell me a story');
    expect(reply.text, isNotEmpty);
    expect(reply.offline, isFalse);
    final emergency = await talk.ask(
        patientId: pid, lang: 'en', firstName: 'Asha', history: const [], text: 'I have chest pain');
    expect(emergency.emergency, isTrue);

    // 5. New phone: log in again, restore everything that was shared.
    final db2 = await newDb();
    final api2 = newClient();
    final user2 = await signIn(api2, patientPhone, 'patient', signUp: false);
    expect(user2.id, user.id);
    final offer = await api2.myPatient();
    final acc2 = await db2.createAccount(phone: patientPhone, role: 'patient', name: 'Asha Devi');
    final pid2 = await db2.restoreFromSnapshot(
        accountId: acc2, phone: patientPhone, snapshot: await api2.snapshot(offer['id'] as String));
    final p2 = (await db2.patientById(pid2))!;
    expect([p2['display_name'], p2['language'], p2['baseline_level']], ['Asha Devi', 'bn', 4]);
    expect((await db2.sessionTimes(pid2)).length, 3);
    expect((await db2.listReminders(pid2)).single.hour, 9);
    expect(await db2.hasConsent(pid2, 'companion'), isTrue);
    expect((await db2.listCareLinks(pid2)).single['status'], 'accepted');
    expect(await SyncService(db2, api2).run(pid2), SyncOutcome.done); // nothing re-sent, no error

    // 6. Withdraw caregiver sharing: the caretaker loses access at once.
    await db2.withdrawConsent(
        patientId: pid2, purpose: 'caregiver_share', byName: 'Asha',
        byRelation: 'self', noticeVersion: 'v2');
    await SyncService(db2, api2).run(pid2);
    expect(await carer.myPatients(), isEmpty);
    await expectLater(carer.report(serverId, 7),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));

    // 7. Erase on the server: the login is gone.
    await api2.eraseServerData(offer['id'] as String);
    final api3 = newClient();
    final otp = ApiOtpService(api3);
    await otp.send(patientPhone, role: 'patient');
    expect(await otp.verify(patientPhone, lastCode(), role: 'patient'), OtpResult.noAccount);
  }, skip: skip);
}
