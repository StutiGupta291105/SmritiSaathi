import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adherence.dart';
import 'package:smriti_assist/core/engagement_alerts.dart';
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


  group('reminder completion', () {
    Future<(String, String)> withReminder({Set<String>? consent}) async {
      final id = await _patient(db, consent ?? {'gameplay', 'reminders'});
      final rid = await db.addReminder(
          patientId: id,
          kind: ReminderKind.medicine,
          label: 'Secret tablet name',
          hour: 9,
          minute: 0,
          createdBy: 'Asha');
      return (id, rid);
    }

    test('marking done needs the reminders purpose', () async {
      final (id, rid) = await withReminder();
      await db.withdrawConsent(
          patientId: id,
          purpose: 'reminders',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      expect(
          () => db.setReminderDone(
              patientId: id,
              reminderId: rid,
              day: DateTime(2026, 3, 10),
              done: true,
              by: 'Asha'),
          throwsA(isA<ConsentRequired>()));
    });

    test('marking twice keeps one row; undo removes it', () async {
      final (id, rid) = await withReminder();
      final day = DateTime(2026, 3, 10);
      for (var i = 0; i < 2; i++) {
        await db.setReminderDone(
            patientId: id, reminderId: rid, day: day, done: true, by: 'Asha');
      }
      expect(await raw.query('reminder_log'), hasLength(1));
      expect(await db.doneKeys(id, days: 3650), {doneKey(rid, day)});
      await db.setReminderDone(
          patientId: id, reminderId: rid, day: day, done: false, by: 'Asha');
      expect(await db.doneKeys(id, days: 3650), isEmpty);
    });

    test('the log and its audit entries hold no reminder text', () async {
      final (id, rid) = await withReminder();
      await db.setReminderDone(
          patientId: id,
          reminderId: rid,
          day: DateTime(2026, 3, 10),
          done: true,
          by: 'Asha');
      final log = await raw.query('reminder_log');
      expect('$log', isNot(contains('Secret')));
      for (final r in await raw.query('audit_log')) {
        expect('${r['detail']}', isNot(contains('Secret')));
      }
    });

    test('listReminders carries the creation time', () async {
      final (id, _) = await withReminder();
      final r = (await db.listReminders(id)).single;
      expect(r.createdAt, isNotNull);
      expect(DateTime.now().difference(r.createdAt!).inMinutes, lessThan(2));
    });

    test('export includes the log and erasure removes it', () async {
      final (id, rid) = await withReminder();
      await db.setReminderDone(
          patientId: id,
          reminderId: rid,
          day: DateTime(2026, 3, 10),
          done: true,
          by: 'Asha');
      final out = await db.exportPatient(id, 'Asha');
      expect(out['reminder_log'] as List, hasLength(1));
      await db.erasePatient(id, 'Asha');
      expect(await raw.query('reminder_log'), isEmpty);
    });
  });


  group('current alerts for the badge', () {
    Future<String> patientWithOldReminder(Set<String> consent) async {
      final id = await _patient(db, consent);
      await raw.insert('reminders', {
        'id': 'r1',
        'patient_id': id,
        'kind': 'medicine',
        'label': '',
        'hour': 0,
        'minute': 0,
        'days_mask': 127,
        'active': 1,
        'created_by': 'x',
        'created_at':
            DateTime.now().toUtc().subtract(const Duration(days: 10)).toIso8601String(),
      });
      return id;
    }

    test('nothing is reported without caregiver_share consent', () async {
      final id = await patientWithOldReminder({'gameplay', 'reminders'});
      expect(await db.currentAlerts(id), isEmpty);
    });

    test('unmarked reminders raise the low-adherence alert; marks clear it',
        () async {
      final id = await patientWithOldReminder(
          {'gameplay', 'reminders', 'caregiver_share'});
      final kinds = (await db.currentAlerts(id)).map((a) => a.kind).toList();
      expect(kinds, contains(AlertKind.lowAdherence));

      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        await db.setReminderDone(
            patientId: id,
            reminderId: 'r1',
            day: DateTime(now.year, now.month, now.day - i),
            done: true,
            by: 'x');
      }
      final after = (await db.currentAlerts(id)).map((a) => a.kind).toList();
      expect(after, isNot(contains(AlertKind.lowAdherence)));
      expect(after, isNot(contains(AlertKind.medicineNotDone)));
    });
  });

  group('upgrade from v3', () {
    test('creates the completion log and keeps existing rows', () async {
      final v3 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 3,
            onCreate: (d, _) async {
              await d.execute('CREATE TABLE patients(id TEXT PRIMARY KEY, name TEXT)');
              await d.insert('patients', {'id': 'p', 'name': 'Keep'});
            },
          ));
      await AppDatabase.upgradeSchema(v3, 3);
      expect((await v3.query('patients')).single['name'], 'Keep');
      await v3.insert('reminder_log', {
        'id': '1',
        'patient_id': 'p',
        'reminder_id': 'r',
        'day': '2026-03-10',
        'marked_at': 'x'
      });
      expect(await v3.query('reminder_log'), hasLength(1));
      await v3.close();
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

  group('server link bookkeeping', () {
    test('nothing is uploaded without the sync purpose', () async {
      final id = await _patient(db, {'gameplay', 'reminders'});
      await db.insertSession(
          patientId: id,
          game: 'memory_match',
          startedAt: DateTime.now(),
          startLevel: 2,
          endLevel: 2,
          trials: 3,
          correct: 3);
      expect((await db.syncBatch(id)).isEmpty, isTrue);
    });

    test('sessions need gameplay and schedules need reminders; no labels leave',
        () async {
      final id = await _patient(db, {'sync', 'gameplay', 'reminders'});
      await db.insertSession(
          patientId: id,
          game: 'memory_match',
          startedAt: DateTime.now(),
          startLevel: 2,
          endLevel: 3,
          trials: 4,
          correct: 3);
      await db.addReminder(
          patientId: id,
          kind: ReminderKind.medicine,
          label: 'Secret tablet name',
          hour: 9,
          minute: 30,
          onDate: DateTime(2026, 3, 10, 9, 30),
          createdBy: 'Asha');
      final b = await db.syncBatch(id);
      expect(b.sessions.single['game'], 'memory_match');
      expect(b.schedules.single['hour'], 9);
      expect(b.schedules.single['on_date'], '2026-03-10');
      expect(b.schedules.single['active'], isTrue);
      expect(b.schedules.single.values.join(), isNot(contains('Secret')));

      await db.withdrawConsent(
          patientId: id,
          purpose: 'gameplay',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      final after = await db.syncBatch(id);
      expect(after.sessions, isEmpty);
      expect(after.schedules, hasLength(1));
    });

    test('consents are reported until marked synced', () async {
      final id = await _patient(db, {'sync'});
      final pending = await db.unsyncedConsents(id);
      expect(pending, isNotEmpty);
      await db.markConsentsSynced([for (final c in pending) c['id'] as String]);
      expect(await db.unsyncedConsents(id), isEmpty);
      await db.withdrawConsent(
          patientId: id,
          purpose: 'sync',
          byName: 'Asha',
          byRelation: 'self',
          noticeVersion: 'v2');
      expect(await db.unsyncedConsents(id), isNotEmpty); // withdrawal must go too
    });

    test('invites saved offline are listed, then take the server status',
        () async {
      final id = await _patient(db, {'caregiver_share'});
      final link = await db.addCareInvite(
          patientId: id,
          kind: 'caregiver',
          name: 'Ravi',
          professionalId: '',
          phone: '+919811111111',
          by: 'Asha');
      expect((await db.unsentInvites(id)).single['id'], link);
      await db.setCareLinkServerId(link, 'srv1');
      expect(await db.unsentInvites(id), isEmpty);
      await db.applyServerLinkStatuses(id, [
        {'id': 'srv1', 'status': 'accepted'}
      ]);
      final rows = await raw.query('care_links', where: 'id = ?', whereArgs: [link]);
      expect(rows.single['status'], 'accepted');
    });

    test('server ids can be linked to the local account and patient', () async {
      final id = await _patient(db, {});
      final acc = (await raw.query('accounts')).single['id'] as String;
      await db.linkServerAccount(acc, 'u-123');
      expect((await db.accountByServerId('u-123'))!['id'], acc);
      await db.setServerPatientId(id, 'sp-1');
      expect((await raw.query('patients')).single['server_patient_id'], 'sp-1');
    });
  });

  group('upgrade from v4', () {
    test('adds the server columns and keeps rows', () async {
      final v4 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 4,
            onCreate: (d, _) async {
              await d.execute('CREATE TABLE accounts(id TEXT PRIMARY KEY)');
              await d.execute('CREATE TABLE patients(id TEXT PRIMARY KEY)');
              await d.execute(
                  'CREATE TABLE consents(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.execute(
                  'CREATE TABLE care_links(id TEXT PRIMARY KEY, patient_id TEXT)');
              await d.insert('consents', {'id': 'c', 'patient_id': 'p'});
            },
          ));
      await AppDatabase.upgradeSchema(v4, 4);
      await AppDatabase.upgradeSchema(v4, 4); // safe to repeat
      final c = (await v4.query('consents')).single;
      expect(c['synced'], 0); // old consents still have to be sent
      expect((await v4.query('care_links')).isEmpty, isTrue);
      await v4.query('care_links', columns: ['phone', 'server_link_id']);
      await v4.query('accounts', columns: ['server_user_id']);
      await v4.query('patients', columns: ['server_patient_id']);
      await v4.close();
    });
  });

  group('restore on a new phone', () {
    final snap = {
      'patient': {
        'id': 'srv-1',
        'display_name': 'Asha',
        'language': 'hi',
        'baseline_level': 3,
        'tz_offset_minutes': 330
      },
      'consents': [
        {
          'purpose': 'gameplay',
          'granted': true,
          'given_by_name': 'Asha',
          'given_by_relation': 'self',
          'notice_version': 'v2',
          'created_at': '2026-03-01T00:00:00Z'
        },
        {
          'purpose': 'sync',
          'granted': true,
          'given_by_name': 'Asha',
          'given_by_relation': 'self',
          'notice_version': 'v2',
          'created_at': '2026-03-01T00:00:00Z'
        },
        {
          'purpose': 'reminders',
          'granted': true,
          'given_by_name': 'Asha',
          'given_by_relation': 'self',
          'notice_version': 'v2',
          'created_at': '2026-03-01T00:00:00Z'
        }
      ],
      'sessions': [
        {
          'id': 's1',
          'game': 'attention',
          'started_at': '2026-03-02T10:00:00Z',
          'ended_at': '2026-03-02T10:05:00Z',
          'start_level': 2,
          'end_level': 3,
          'trials': 10,
          'correct': 8,
          'level_stats': null
        }
      ],
      'schedules': [
        {
          'id': 'r1',
          'kind': 'medicine',
          'hour': 9,
          'minute': 0,
          'days_mask': 127,
          'on_date': null,
          'active': true,
          'created_at': '2026-03-01T00:00:00Z'
        }
      ],
      'marks': [
        {'reminder_id': 'r1', 'day': '2026-03-02', 'marked_at': '2026-03-02T09:05:00Z'}
      ],
      'links': [
        {
          'id': 'l1',
          'kind': 'caretaker',
          'name': 'Ravi',
          'professional_id': '',
          'status': 'accepted'
        }
      ],
    };

    test('rebuilds the patient, history and consent state as already synced',
        () async {
      final acc = await db.createAccount(phone: _phone, role: 'patient', name: 'Asha');
      final id = await db.restoreFromSnapshot(
          accountId: acc, phone: _phone, snapshot: snap);
      final p = (await db.patientById(id))!;
      expect([p['display_name'], p['language'], p['baseline_level'], p['setup_stage']],
          ['Asha', 'hi', 3, 0]);
      expect(p['server_patient_id'], 'srv-1');
      expect(await db.hasConsent(id, 'gameplay'), isTrue);
      expect(await db.hasConsent(id, 'family_contacts'), isFalse);
      expect(await db.unsyncedConsents(id), isEmpty);
      expect(await db.unsyncedSessions(id), isEmpty);
      expect((await db.sessionTimes(id)).length, 1);
      final r = (await db.listReminders(id)).single;
      expect([r.hour, r.active], [9, true]);
      expect((await db.listCareLinks(id)).single['status'], 'accepted');
      expect(await db.verifyAuditChain(), isTrue);
    });

    test('restored data is not uploaded again', () async {
      final acc = await db.createAccount(phone: _phone, role: 'patient', name: 'Asha');
      final id = await db.restoreFromSnapshot(
          accountId: acc, phone: _phone, snapshot: snap);
      expect((await db.unsentInvites(id)), isEmpty);
      expect((await db.syncBatch(id)).sessions, isEmpty);
    });
  });

  group('upgrade from v5', () {
    test('adds the starting-level and verified columns and keeps rows', () async {
      final v5 = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 5,
            onCreate: (d, _) async {
              await d.execute('CREATE TABLE patients(id TEXT PRIMARY KEY, name TEXT)');
              await d.execute('CREATE TABLE care_links(id TEXT PRIMARY KEY, status TEXT)');
              await d.insert('care_links', {'id': 'l', 'status': 'accepted'});
            },
          ));
      await AppDatabase.upgradeSchema(v5, 5);
      await AppDatabase.upgradeSchema(v5, 5); // safe to repeat
      final l = (await v5.query('care_links')).single;
      expect([l['status'], l['verified']], ['accepted', 0]);
      await v5.query('patients', columns: ['server_baseline']);
      await v5.close();
    });
  });
}
