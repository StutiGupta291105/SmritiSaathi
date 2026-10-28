import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/reminder_schedule.dart';
import 'package:smriti_assist/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _phone = '+919876543210';

Future<(AppDatabase, Database)> _open({DateTime Function()? clock}) async {
  sqfliteFfiInit();
  final raw = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: AppDatabase.schemaVersion,
      onCreate: (d, _) => AppDatabase.createSchema(d),
    ),
  );
  return (AppDatabase.forTesting(raw, clock: clock), raw);
}

/// Account + patient with the given consents granted.
Future<String> _patient(AppDatabase db, Set<String> granted) async {
  final accountId =
      await db.createAccount(phone: _phone, role: 'patient', name: 'Asha');
  final id = await db.createPatient(
    accountId: accountId,
    phone: _phone,
    displayName: 'Asha',
    baselineLevel: 2,
    language: 'en',
    createdBy: 'Asha',
  );
  await db.recordConsent(
    patientId: id,
    purposes: {for (final p in kConsentPurposes) p: granted.contains(p)},
    givenByName: 'Asha',
    givenByRelation: 'self',
    noticeVersion: 'v2',
  );
  return id;
}

void main() {
  late AppDatabase db;
  late Database raw;

  setUp(() async {
    final opened = await _open();
    db = opened.$1;
    raw = opened.$2;
  });

  tearDown(() => raw.close());

  group('consent is enforced', () {
    test('game results need the gameplay purpose', () async {
      final id = await _patient(db, {});
      Future<void> save() => db.insertSession(
          patientId: id,
          game: 'memory_match',
          startedAt: DateTime.now(),
          startLevel: 2,
          endLevel: 2,
          trials: 3,
          correct: 3);
      expect(save, throwsA(isA<ConsentRequired>()));
      await db.recordConsent(
          patientId: id,
          purposes: {'gameplay': true},
          givenByName: 'Asha',
          givenByRelation: 'self',
          noticeVersion: 'v2');
      await save();
      expect((await db.sessionTimes(id)).length, 1);
    });

    test('withdrawing reminders switches existing reminders off', () async {
      final id = await _patient(db, {'gameplay', 'reminders'});
      await db.addReminder(
          patientId: id,
          kind: ReminderKind.medicine,
          label: 'Tablet',
          hour: 9,
          minute: 0,
          createdBy: 'Asha');
      await db.withdrawConsent(
          patientId: id,
          purpose: 'reminders',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      expect((await db.listReminders(id)).single.active, isFalse);
      expect(
          () => db.addReminder(
              patientId: id,
              kind: ReminderKind.hydration,
              label: '',
              hour: 10,
              minute: 0,
              createdBy: 'Asha'),
          throwsA(isA<ConsentRequired>()));
    });

    test('family contacts need consent and hide on withdrawal', () async {
      final id = await _patient(db, {'gameplay'});
      Future<void> add() => db.addFamilyMember(
          patientId: id,
          name: 'Ravi',
          phone: '+919000000001',
          relation: 'son',
          by: 'Asha');
      expect(add, throwsA(isA<ConsentRequired>()));

      await db.recordConsent(
          patientId: id,
          purposes: {'family_contacts': true},
          givenByName: 'Asha',
          givenByRelation: 'self',
          noticeVersion: 'v2');
      await add();
      expect((await db.listFamily(id)).length, 1);

      await db.withdrawConsent(
          patientId: id,
          purpose: 'family_contacts',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      expect(await db.listFamily(id), isEmpty);
    });

    test('doctor invite needs doctor_share and is revoked on withdrawal',
        () async {
      final id = await _patient(db, {'gameplay'});
      Future<void> invite() => db.addCareInvite(
          patientId: id,
          kind: 'doctor',
          name: 'Dr Rao',
          professionalId: 'REG123',
          by: 'Asha');
      expect(invite, throwsA(isA<ConsentRequired>()));

      await db.recordConsent(
          patientId: id,
          purposes: {'doctor_share': true},
          givenByName: 'Asha',
          givenByRelation: 'self',
          noticeVersion: 'v2');
      await invite();
      expect((await db.listCareLinks(id)).single['status'], 'pending');

      await db.withdrawConsent(
          patientId: id,
          purpose: 'doctor_share',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      expect((await db.listCareLinks(id)).single['status'], 'revoked');
    });

    test('nothing is queued for sync without the sync purpose', () async {
      final id = await _patient(db, {'gameplay'});
      await db.insertSession(
          patientId: id,
          game: 'attention',
          startedAt: DateTime.now(),
          startLevel: 1,
          endLevel: 1,
          trials: 1,
          correct: 1);
      expect(await db.unsyncedSessions(id), isEmpty);
    });
  });

  group('accounts', () {
    test('same phone and role cannot register twice; other role can', () async {
      await db.createAccount(phone: _phone, role: 'patient', name: 'A');
      expect(() => db.createAccount(phone: _phone, role: 'patient', name: 'B'),
          throwsA(isA<StateError>()));
      await db.createAccount(phone: _phone, role: 'doctor', name: 'C');
      expect(await db.accountByPhoneRole(_phone, 'doctor'), isNotNull);
      expect(await db.accountByPhoneRole('+919111111111', 'patient'), isNull);
    });
  });

  group('audit log', () {
    test('chain verifies, and detects tampering', () async {
      final id = await _patient(db, {'gameplay', 'reminders'});
      await db.setVoiceEnabled(id, false, 'Asha');
      expect(await db.verifyAuditChain(), isTrue);

      await raw.update('audit_log', {'detail': 'edited'},
          where: 'action = ?', whereArgs: ['voice_disabled']);
      expect(await db.verifyAuditChain(), isFalse);
    });

    test('detects a deleted entry in the middle', () async {
      final id = await _patient(db, {'gameplay'});
      await db.setVoiceEnabled(id, false, 'Asha');
      await db.setVoiceEnabled(id, true, 'Asha');
      await raw.delete('audit_log',
          where: 'action = ?', whereArgs: ['voice_disabled']);
      expect(await db.verifyAuditChain(), isFalse);
    });

    test('retention never purges entries younger than 180 days', () async {
      final id = await _patient(db, {'gameplay'});
      await raw.update('audit_log', {'synced': 1});
      expect(await db.purgeAuditOlderThan(1), 0); // asked for 1 day, floor is 180
      expect(await db.verifyAuditChain(), isTrue);
      expect(id, isNotEmpty);
    });

    test('purging old shipped entries keeps the chain valid', () async {
      await _patient(db, {'gameplay'});
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 400))
          .toIso8601String();
      // Age the first entries, and mark them as shipped.
      await raw.execute(
          'UPDATE audit_log SET ts = ?, synced = 1 WHERE rowid <= 2', [old]);
      final removed = await db.purgeAuditOlderThan(180);
      expect(removed, 2);
      // The oldest surviving entry anchors the chain, so it still verifies.
      // (The two aged rows were edited above, which is why only they go.)
      expect(await db.verifyAuditChain(), isTrue);
    });

    test('entries hold no phone numbers or names of people', () async {
      final id = await _patient(db, {'gameplay', 'family_contacts'});
      await db.addFamilyMember(
          patientId: id,
          name: 'Ravi Kumar',
          phone: '+919000000001',
          relation: 'son',
          by: 'Asha');
      final rows = await raw.query('audit_log');
      for (final r in rows) {
        final text = '${r['actor']} ${r['detail']}';
        expect(text, isNot(contains('+91')));
        expect(text, isNot(contains('Ravi')));
      }
    });
  });

  group('access and erasure', () {
    test('export covers all tables and does not dump photo bytes', () async {
      final id = await _patient(db, {'gameplay', 'family_contacts'});
      await db.updateProfileBasics(
          patientId: id,
          dob: DateTime(1950, 5, 1),
          photo: List<int>.filled(1000, 7),
          by: 'Asha');
      await db.addFamilyMember(
          patientId: id,
          name: 'Ravi',
          phone: '+919000000001',
          relation: 'son',
          photo: List<int>.filled(500, 9),
          by: 'Asha');
      final out = await db.exportPatient(id, 'Asha');
      for (final k in [
        'account',
        'patient',
        'consents',
        'sessions',
        'reminders',
        'family_members',
        'care_links'
      ]) {
        expect(out.containsKey(k), isTrue, reason: k);
      }
      final patient = (out['patient'] as List).single as Map;
      expect(patient['photo'], '<photo: 1000 bytes>');
      expect(patient['dob'], '1950-05-01');
      final member = (out['family_members'] as List).single as Map;
      expect(member['photo'], '<photo: 500 bytes>');
    });

    test('erase removes the patient, everything linked, and the account',
        () async {
      final id = await _patient(db, {'gameplay', 'reminders', 'family_contacts'});
      await db.addFamilyMember(
          patientId: id,
          name: 'Ravi',
          phone: '+919000000001',
          relation: 'son',
          by: 'Asha');
      await db.addReminder(
          patientId: id,
          kind: ReminderKind.hydration,
          label: '',
          hour: 10,
          minute: 0,
          createdBy: 'Asha');
      await db.insertSession(
          patientId: id,
          game: 'routine',
          startedAt: DateTime.now(),
          startLevel: 2,
          endLevel: 2,
          trials: 4,
          correct: 3);

      await db.erasePatient(id, 'Asha');

      for (final t in [
        'patients',
        'accounts',
        'consents',
        'sessions',
        'reminders',
        'family_members',
        'care_links'
      ]) {
        expect(await raw.query(t), isEmpty, reason: t);
      }
      final log = await raw.query('audit_log', where: "action = 'patient_erased'");
      expect(log.length, 1);
      expect(await db.verifyAuditChain(), isTrue);
    });
  });


  group('learned difficulty', () {
    Future<void> play(String id, String game, String stats, int trials,
        int correct) =>
        db.insertSession(
            patientId: id,
            game: game,
            startedAt: DateTime.now(),
            startLevel: 2,
            endLevel: 2,
            trials: trials,
            correct: correct,
            levelStats: stats);

    test('level tallies are aggregated across sessions of one game', () async {
      final id = await _patient(db, {'gameplay'});
      await play(id, 'attention', '{"2":[10,8],"3":[5,2]}', 15, 10);
      await play(id, 'attention', '{"2":[6,6]}', 6, 6);
      await play(id, 'routine', '{"4":[9,9]}', 9, 9); // other game, ignored
      final stats = await db.levelStats(id, 'attention');
      final byLevel = {for (final s in stats) s.level: [s.trials, s.correct]};
      expect(byLevel, {2: [16, 14], 3: [5, 2]});
    });

    test('with no history a game starts at the caregiver baseline', () async {
      final id = await _patient(db, {'gameplay'});
      expect(await db.recommendedStartLevel(id, 'memory_match', 3), 3);
    });

    test('strong history raises the start, but only within the band', () async {
      final id = await _patient(db, {'gameplay'});
      for (var i = 0; i < 6; i++) {
        await play(id, 'memory_match', '{"3":[10,10]}', 10, 10);
      }
      expect(await db.recommendedStartLevel(id, 'memory_match', 2), 3);
      // Baseline 2 means the band is 1..3, so it can never go above 3.
      for (var i = 0; i < 6; i++) {
        await play(id, 'memory_match', '{"5":[10,10]}', 10, 10);
      }
      expect(await db.recommendedStartLevel(id, 'memory_match', 2), 3);
    });

    test('sessions saved without level tallies are ignored by the model',
        () async {
      final id = await _patient(db, {'gameplay'});
      await db.insertSession(
          patientId: id,
          game: 'routine',
          startedAt: DateTime.now(),
          startLevel: 1,
          endLevel: 1,
          trials: 5,
          correct: 0);
      expect(await db.levelStats(id, 'routine'), isEmpty);
      expect(await db.sessionRecords(id), hasLength(1));
    });
  });

  group('caregiver PIN', () {
    test('is stored hashed and verifies only the right PIN', () async {
      final id = await _patient(db, {'gameplay'});
      expect(await db.hasCaregiverPin(id), isFalse);
      await db.setCaregiverPin(id, '4821', 'caregiver');
      expect(await db.hasCaregiverPin(id), isTrue);

      final row = (await raw.query('patients')).single;
      expect(row['caregiver_pin_hash'], isNot(contains('4821')));
      expect(row['caregiver_pin_salt'], isNotNull);

      expect(await db.verifyCaregiverPin(id, '0000', 'caregiver'),
          PinResult.wrong);
      expect(await db.verifyCaregiverPin(id, '4821', 'caregiver'),
          PinResult.ok);
    });

    test('locks after 5 wrong tries and unlocks after the lock period',
        () async {
      var now = DateTime(2026, 3, 1, 9);
      final opened = await _open(clock: () => now);
      final d = opened.$1;
      final id = await _patient(d, {'gameplay'});
      await d.setCaregiverPin(id, '1234', 'caregiver');
      for (var i = 0; i < 4; i++) {
        expect(await d.verifyCaregiverPin(id, '9999', 'caregiver'),
            PinResult.wrong);
      }
      expect(await d.verifyCaregiverPin(id, '9999', 'caregiver'),
          PinResult.locked);
      // The right PIN is refused while locked.
      expect(await d.verifyCaregiverPin(id, '1234', 'caregiver'),
          PinResult.locked);
      now = now.add(const Duration(minutes: AppDatabase.pinLockMinutes + 1));
      expect(await d.verifyCaregiverPin(id, '1234', 'caregiver'),
          PinResult.ok);
      await opened.$2.close();
    });

    test('outcomes are audited without the PIN itself', () async {
      final id = await _patient(db, {'gameplay'});
      await db.setCaregiverPin(id, '7777', 'caregiver');
      await db.verifyCaregiverPin(id, '1111', 'caregiver');
      await db.verifyCaregiverPin(id, '7777', 'caregiver');
      final log = await raw.query('audit_log');
      final actions = log.map((r) => r['action']).toList();
      expect(actions, containsAll(
          ['caregiver_pin_set', 'caregiver_pin_failed', 'caregiver_area_opened']));
      for (final r in log) {
        expect('${r['detail']}', isNot(contains('7777')));
        expect('${r['detail']}', isNot(contains('1111')));
      }
    });

    test('PIN hash and salt are never part of the data export', () async {
      final id = await _patient(db, {'gameplay'});
      await db.setCaregiverPin(id, '4821', 'caregiver');
      final out = await db.exportPatient(id, 'Asha');
      final patient = (out['patient'] as List).single as Map;
      expect(patient.containsKey('caregiver_pin_hash'), isFalse);
      expect(patient.containsKey('caregiver_pin_salt'), isFalse);
    });
  });

  group('upgrade from the v1 test build', () {
    test('old orphan rows are removed and the new schema is in place', () async {
      final v1 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 1,
            onCreate: (d, _) async {
              await d.execute('''CREATE TABLE patients(
                id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
                language TEXT NOT NULL DEFAULT 'en', baseline_level INTEGER NOT NULL,
                voice_enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)''');
              await d.execute(
                  'CREATE TABLE consents(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.execute(
                  'CREATE TABLE sessions(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.execute(
                  'CREATE TABLE reminders(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.insert('patients', {
                'id': 'old',
                'display_name': 'Old',
                'baseline_level': 2,
                'created_at': 'x'
              });
              await d.insert('sessions', {'id': 's', 'patient_id': 'old'});
            },
          ));
      await AppDatabase.upgradeSchema(v1, 1);
      expect(await v1.query('patients'), isEmpty);
      expect(await v1.query('sessions'), isEmpty);
      await v1.insert('accounts', {
        'id': 'a',
        'phone': _phone,
        'role': 'patient',
        'name': 'N',
        'created_at': 'x'
      });
      await v1.insert('patients', {
        'id': 'p',
        'account_id': 'a',
        'display_name': 'N',
        'baseline_level': 2,
        'created_at': 'x'
      });
      final row = (await v1.query('patients')).single;
      expect(row['setup_stage'], 0);
      await v1.close();
    });
  });

  group('upgrade from v2', () {
    test('adds level stats and PIN columns and keeps existing rows', () async {
      final v2 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 2,
            onCreate: (d, _) async {
              await d.execute('''CREATE TABLE patients(
                id TEXT PRIMARY KEY, account_id TEXT, display_name TEXT NOT NULL,
                phone TEXT, dob TEXT, photo BLOB,
                language TEXT NOT NULL DEFAULT 'en', baseline_level INTEGER NOT NULL,
                voice_enabled INTEGER NOT NULL DEFAULT 1,
                setup_stage INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''');
              await d.execute(
                  'CREATE TABLE sessions(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.insert('patients', {
                'id': 'p',
                'display_name': 'Keep',
                'baseline_level': 3,
                'created_at': 'x'
              });
              await d.insert('sessions', {'id': 's', 'patient_id': 'p'});
            },
          ));
      await AppDatabase.upgradeSchema(v2, 2);
      final patient = (await v2.query('patients')).single;
      expect(patient['display_name'], 'Keep'); // v2 -> v3 must not wipe data
      expect(patient.containsKey('caregiver_pin_hash'), isTrue);
      expect((await v2.query('sessions')).single.containsKey('level_stats'), isTrue);
      await v2.close();
    });
  });
}
