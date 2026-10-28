import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/reminder_schedule.dart';

/// Thrown when an operation needs a purpose the patient has not consented to
/// (or has withdrawn). DPDP: processing must stop without valid consent.
class ConsentRequired implements Exception {
  ConsentRequired(this.purpose);
  final String purpose;
  @override
  String toString() => 'ConsentRequired($purpose)';
}

/// Every purpose the app can ask consent for. Each new personal-data feature
/// adds a purpose here, a requireConsent gate, and export/erase coverage.
const kConsentPurposes = [
  'gameplay',
  'reminders',
  'family_contacts',
  'doctor_share',
  'caregiver_share',
  'location',
  'sync',
];

/// CERT-In directions: keep logs for a rolling 180 days (we never purge
/// younger than this, whatever the caller passes).
const int kMinLogRetentionDays = 180;

/// Offline-first encrypted store.
///
/// Compliance notes:
///  * CERT-In / security: DB is SQLCipher-encrypted; the key is random and kept
///    in the platform keystore, never in code or prefs.
///  * DPDP: consent is recorded per purpose with who gave it (patient or
///    guardian); access ([exportPatient]) and erasure ([erasePatient]) are
///    implemented from day one; data collected is minimal.
///  * Every sensitive action goes to [audit_log] (append-only from app code).
///  * `synced = 0` rows form the sync queue for when connectivity returns.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;
  static const _uuid = Uuid();

  static Future<AppDatabase> open() async {
    final key = await _getOrCreateKey();
    final path = p.join(await getDatabasesPath(), 'smriti_assist.db');
    final db = await openDatabase(
      path,
      password: key,
      version: schemaVersion,
      onUpgrade: (db, o, n) => upgradeSchema(db, o),
      onCreate: (db, _) => createSchema(db),
    );
    return AppDatabase._(db);
  }

  static const schemaVersion = 2;

  /// Fresh install: the full current schema.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE patients(
        id TEXT PRIMARY KEY,
        account_id TEXT,
        display_name TEXT NOT NULL,
        phone TEXT,
        dob TEXT,
        photo BLOB,
        language TEXT NOT NULL DEFAULT 'en',
        baseline_level INTEGER NOT NULL,
        voice_enabled INTEGER NOT NULL DEFAULT 1,
        setup_stage INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    await _createAccountTables(db);
    await db.execute('''
      CREATE TABLE consents(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        purpose TEXT NOT NULL,
        granted INTEGER NOT NULL,
        given_by_name TEXT NOT NULL,
        given_by_relation TEXT NOT NULL,   -- 'self' or guardian relationship
        notice_version TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE sessions(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        game TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        start_level INTEGER NOT NULL,
        end_level INTEGER NOT NULL,
        trials INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE audit_log(
        id TEXT PRIMARY KEY,
        ts TEXT NOT NULL,
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        detail TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        hash TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE reminders(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        label TEXT NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        days_mask INTEGER NOT NULL DEFAULT 127,
        on_date TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
  }

  /// Upgrade from an older installed version.
  static Future<void> upgradeSchema(Database db, int oldVersion) async {
    if (oldVersion < 2) {
      // v1 was a test build with no account system. Its patient rows have
      // no owner and could never be exported or erased by a login, so
      // they are removed rather than left orphaned (DPDP).
      for (final t in ['sessions', 'reminders', 'consents', 'patients']) {
        await db.delete(t);
      }
      for (final col in [
        'account_id TEXT',
        'phone TEXT',
        'dob TEXT',
        'photo BLOB',
        'setup_stage INTEGER NOT NULL DEFAULT 0',
      ]) {
        await db.execute('ALTER TABLE patients ADD COLUMN $col');
      }
      await _createAccountTables(db);
    }
  }

  /// For tests: wraps an already-open database (for example in-memory SQLite).
  @visibleForTesting
  AppDatabase.forTesting(this._db);

  static Future<void> _createAccountTables(Database db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id TEXT PRIMARY KEY,
        phone TEXT NOT NULL,
        role TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(phone, role)
      )''');
    await db.execute('''
      CREATE TABLE family_members(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        relation TEXT NOT NULL,
        photo BLOB,
        created_at TEXT NOT NULL
      )''');
    // Invites to a doctor or caregiver. Status moves pending -> accepted or
    // declined once the backend exists; 'revoked' when consent is withdrawn.
    await db.execute('''
      CREATE TABLE care_links(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        name TEXT NOT NULL,
        professional_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL
      )''');
  }

  static Future<String> _getOrCreateKey() async {
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: 'db_key');
    if (key == null) {
      final rnd = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await storage.write(key: 'db_key', value: key);
    }
    return key;
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  static const _genesis = 'GENESIS';

  static String _entryHash(String prev, String id, String ts, String actor,
          String action, String detail) =>
      sha256
          .convert(utf8.encode(jsonEncode([prev, id, ts, actor, action, detail])))
          .toString();

  /// Append-only, hash-chained: each entry commits to the one before, so
  /// edits or deletions in the middle are detectable by [verifyAuditChain].
  /// Details must never contain health content (labels, names of medicines).
  Future<void> audit(String actor, String action, String detail) async {
    final last = await _db.query('audit_log',
        columns: ['hash'], orderBy: 'rowid DESC', limit: 1);
    final prev = last.isEmpty ? _genesis : last.first['hash'] as String;
    final id = _uuid.v4();
    final ts = _now();
    await _db.insert('audit_log', {
      'id': id,
      'ts': ts,
      'actor': actor,
      'action': action,
      'detail': detail,
      'prev_hash': prev,
      'hash': _entryHash(prev, id, ts, actor, action, detail),
    });
  }

  /// True when no entry has been altered or removed from the middle. The
  /// oldest surviving entry anchors the chain, so retention purges stay valid.
  Future<bool> verifyAuditChain() async {
    final rows = await _db.query('audit_log', orderBy: 'rowid ASC');
    String? expectedPrev;
    for (final r in rows) {
      final prev = r['prev_hash'] as String;
      if (expectedPrev != null && prev != expectedPrev) return false;
      final h = _entryHash(prev, r['id'] as String, r['ts'] as String,
          r['actor'] as String, r['action'] as String, r['detail'] as String);
      if (h != r['hash']) return false;
      expectedPrev = h;
    }
    return true;
  }

  /// Retention job: drops audit entries older than the retention window
  /// (never less than [kMinLogRetentionDays]). Only entries already uploaded
  /// to the central log store are removed, so nothing is lost before it has
  /// been shipped.
  Future<int> purgeAuditOlderThan(int days) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: max(days, kMinLogRetentionDays)))
        .toIso8601String();
    return _db.delete('audit_log',
        where: 'ts < ? AND synced = 1', whereArgs: [cutoff]);
  }

  // ---- patients / caregiver baseline -------------------------------------

  // ---- accounts ----------------------------------------------------------

  /// Throws [StateError] if the phone number already has an account for the
  /// role. Phone numbers are stored in E.164 form. Audit entries never hold
  /// the number itself, only the account id.
  Future<String> createAccount({
    required String phone,
    required String role,
    required String name,
  }) async {
    final existing = await accountByPhoneRole(phone, role);
    if (existing != null) throw StateError('account_exists');
    final id = _uuid.v4();
    await _db.insert('accounts', {
      'id': id,
      'phone': phone,
      'role': role,
      'name': name,
      'created_at': _now(),
    });
    await audit('system', 'account_created', 'account=$id role=$role');
    return id;
  }

  Future<Map<String, Object?>?> accountByPhoneRole(
      String phone, String role) async {
    final rows = await _db.query('accounts',
        where: 'phone = ? AND role = ?', whereArgs: [phone, role], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> accountById(String id) async {
    final rows =
        await _db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> recordLogin(String accountId) =>
      audit('system', 'login', 'account=$accountId');

  Future<void> recordLogout(String accountId) =>
      audit('system', 'logout', 'account=$accountId');

  // ---- patients / caregiver baseline -------------------------------------

  Future<String> createPatient({
    required String accountId,
    required String phone,
    required String displayName,
    required int baselineLevel,
    required String language,
    required String createdBy,
  }) async {
    final id = _uuid.v4();
    await _db.insert('patients', {
      'id': id,
      'account_id': accountId,
      'phone': phone,
      'display_name': displayName,
      'language': language,
      'baseline_level': baselineLevel,
      'setup_stage': 0,
      'created_at': _now(),
    });
    await audit(createdBy, 'patient_created',
        'patient=$id account=$accountId baseline=$baselineLevel');
    return id;
  }

  Future<Map<String, Object?>?> patientForAccount(String accountId) async {
    final rows = await _db.query('patients',
        where: 'account_id = ?', whereArgs: [accountId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Profile basics. [photo] is stored inside the encrypted database (never as
  /// a loose file). Pass [clearPhoto] to remove it.
  Future<void> updateProfileBasics({
    required String patientId,
    DateTime? dob,
    List<int>? photo,
    bool clearPhoto = false,
    String? language,
    required String by,
  }) async {
    final values = <String, Object?>{};
    if (dob != null) values['dob'] = dob.toIso8601String().substring(0, 10);
    if (photo != null) values['photo'] = Uint8List.fromList(photo);
    if (clearPhoto) values['photo'] = null;
    if (language != null) values['language'] = language;
    if (values.isEmpty) return;
    await _db.update('patients', values,
        where: 'id = ?', whereArgs: [patientId]);
    // Which fields changed, never their values.
    await audit(by, 'profile_updated',
        'patient=$patientId fields=${values.keys.join(',')}');
  }

  /// Setup progress, so the profile flow resumes after the app is closed.
  /// 0 about you, 1 family, 2 care team, 3 routine, 4 permissions, 5 done.
  Future<void> setSetupStage(String patientId, int stage) => _db.update(
      'patients', {'setup_stage': stage},
      where: 'id = ?', whereArgs: [patientId]);

  // ---- family members ----------------------------------------------------

  Future<String> addFamilyMember({
    required String patientId,
    required String name,
    required String phone,
    required String relation,
    List<int>? photo,
    required String by,
  }) async {
    await requireConsent(patientId, 'family_contacts');
    final id = _uuid.v4();
    await _db.insert('family_members', {
      'id': id,
      'patient_id': patientId,
      'name': name,
      'phone': phone,
      'relation': relation,
      'photo': photo == null ? null : Uint8List.fromList(photo),
      'created_at': _now(),
    });
    await audit(by, 'family_member_added',
        'patient=$patientId member=$id relation=$relation');
    return id;
  }

  /// Empty while the 'family_contacts' purpose is not consented (processing
  /// stops on withdrawal even though the rows are kept until erasure).
  Future<List<Map<String, Object?>>> listFamily(String patientId) async {
    if (!await hasConsent(patientId, 'family_contacts')) return const [];
    return _db.query('family_members',
        where: 'patient_id = ?', whereArgs: [patientId], orderBy: 'rowid');
  }

  Future<void> deleteFamilyMember(
      String patientId, String memberId, String by) async {
    await _db.delete('family_members',
        where: 'id = ? AND patient_id = ?', whereArgs: [memberId, patientId]);
    await audit(by, 'family_member_deleted',
        'patient=$patientId member=$memberId');
  }

  // ---- care team (doctor / caregiver invites) ----------------------------

  /// Records an invite as 'pending'. Delivery to the doctor or caregiver and
  /// their acceptance need the online service; until then nothing is shared.
  Future<String> addCareInvite({
    required String patientId,
    required String kind, // 'doctor' or 'caregiver'
    required String name,
    required String professionalId,
    required String by,
  }) async {
    assert(kind == 'doctor' || kind == 'caregiver');
    await requireConsent(
        patientId, kind == 'doctor' ? 'doctor_share' : 'caregiver_share');
    final id = _uuid.v4();
    await _db.insert('care_links', {
      'id': id,
      'patient_id': patientId,
      'kind': kind,
      'name': name,
      'professional_id': professionalId,
      'status': 'pending',
      'created_at': _now(),
    });
    await audit(by, 'care_invite_created',
        'patient=$patientId link=$id kind=$kind');
    return id;
  }

  Future<List<Map<String, Object?>>> listCareLinks(String patientId) =>
      _db.query('care_links',
          where: 'patient_id = ?', whereArgs: [patientId], orderBy: 'rowid');

  /// Baseline changes are always attributed and reasoned (also useful as
  /// evidence for the research paper).
  Future<void> setBaseline({
    required String patientId,
    required int newLevel,
    required String caregiverName,
    required String reason,
  }) async {
    final old = await _db.query('patients',
        columns: ['baseline_level'], where: 'id = ?', whereArgs: [patientId]);
    await _db.update('patients', {'baseline_level': newLevel},
        where: 'id = ?', whereArgs: [patientId]);
    await audit(caregiverName, 'baseline_changed',
        'patient=$patientId ${old.first['baseline_level']}->$newLevel reason=$reason');
  }

  // ---- consent (DPDP) ----------------------------------------------------

  Future<void> recordConsent({
    required String patientId,
    required Map<String, bool> purposes,
    required String givenByName,
    required String givenByRelation,
    required String noticeVersion,
  }) async {
    final batch = _db.batch();
    purposes.forEach((purpose, granted) {
      batch.insert('consents', {
        'id': _uuid.v4(),
        'patient_id': patientId,
        'purpose': purpose,
        'granted': granted ? 1 : 0,
        'given_by_name': givenByName,
        'given_by_relation': givenByRelation,
        'notice_version': noticeVersion,
        'created_at': _now(),
      });
    });
    await batch.commit(noResult: true);
    await audit(givenByName, 'consent_recorded',
        'patient=$patientId relation=$givenByRelation purposes=${purposes.entries.map((e) => '${e.key}:${e.value}').join(',')}');
  }

  /// Latest decision per purpose (withdrawal = a newer row with granted = 0).
  Future<bool> hasConsent(String patientId, String purpose) async {
    final rows = await _db.query('consents',
        where: 'patient_id = ? AND purpose = ?',
        whereArgs: [patientId, purpose],
        orderBy: 'rowid DESC',
        limit: 1);
    return rows.isNotEmpty && rows.first['granted'] == 1;
  }

  Future<void> requireConsent(String patientId, String purpose) async {
    if (!await hasConsent(patientId, purpose)) throw ConsentRequired(purpose);
  }

  /// Withdrawing must be as easy as giving. Stops the related processing
  /// immediately; data already held is removed via [erasePatient] on request.
  Future<void> withdrawConsent({
    required String patientId,
    required String purpose,
    required String byName,
    required String byRelation,
    required String noticeVersion,
  }) async {
    await _db.insert('consents', {
      'id': _uuid.v4(),
      'patient_id': patientId,
      'purpose': purpose,
      'granted': 0,
      'given_by_name': byName,
      'given_by_relation': byRelation,
      'notice_version': noticeVersion,
      'created_at': _now(),
    });
    if (purpose == 'reminders') {
      await _db.update('reminders', {'active': 0},
          where: 'patient_id = ?', whereArgs: [patientId]);
    }
    // Withdrawing sharing consent revokes the matching doctor/caregiver links.
    final revokedKind = switch (purpose) {
      'doctor_share' => 'doctor',
      'caregiver_share' => 'caregiver',
      _ => null,
    };
    if (revokedKind != null) {
      await _db.update('care_links', {'status': 'revoked'},
          where: 'patient_id = ? AND kind = ?',
          whereArgs: [patientId, revokedKind]);
    }
    await audit(byName, 'consent_withdrawn',
        'patient=$patientId relation=$byRelation purpose=$purpose');
  }

  Future<Map<String, bool>> consentState(String patientId) async => {
        for (final purpose in kConsentPurposes)
          purpose: await hasConsent(patientId, purpose),
      };

  // ---- reminders ---------------------------------------------------------

  Reminder _reminderFrom(Map<String, Object?> r) => Reminder(
        id: r['id'] as String,
        kind: ReminderKind.values.byName(r['kind'] as String),
        label: r['label'] as String,
        hour: r['hour'] as int,
        minute: r['minute'] as int,
        daysMask: r['days_mask'] as int,
        onDate: r['on_date'] == null
            ? null
            : DateTime.parse(r['on_date'] as String),
        active: r['active'] == 1,
      );

  Future<String> addReminder({
    required String patientId,
    required ReminderKind kind,
    required String label,
    required int hour,
    required int minute,
    int daysMask = 127,
    DateTime? onDate,
    required String createdBy,
  }) async {
    await requireConsent(patientId, 'reminders');
    final id = _uuid.v4();
    await _db.insert('reminders', {
      'id': id,
      'patient_id': patientId,
      'kind': kind.name,
      'label': label,
      'hour': hour,
      'minute': minute,
      'days_mask': daysMask,
      'on_date': onDate?.toIso8601String(),
      'active': 1,
      'created_by': createdBy,
      'created_at': _now(),
    });
    // Audit records the fact, never the label.
    await audit(createdBy, 'reminder_added',
        'patient=$patientId reminder=$id kind=${kind.name}');
    return id;
  }

  Future<List<Reminder>> listReminders(String patientId) async {
    final rows = await _db.query('reminders',
        where: 'patient_id = ?',
        whereArgs: [patientId],
        orderBy: 'hour, minute');
    return rows.map(_reminderFrom).toList();
  }

  Future<void> setReminderActive(
      String patientId, String reminderId, bool active, String by) async {
    if (active) await requireConsent(patientId, 'reminders');
    await _db.update('reminders', {'active': active ? 1 : 0},
        where: 'id = ? AND patient_id = ?', whereArgs: [reminderId, patientId]);
    await audit(by, 'reminder_${active ? 'enabled' : 'disabled'}',
        'patient=$patientId reminder=$reminderId');
  }

  Future<void> deleteReminder(
      String patientId, String reminderId, String by) async {
    await _db.delete('reminders',
        where: 'id = ? AND patient_id = ?', whereArgs: [reminderId, patientId]);
    await audit(by, 'reminder_deleted',
        'patient=$patientId reminder=$reminderId');
  }

  // ---- sessions ----------------------------------------------------------

  Future<void> insertSession({
    required String patientId,
    required String game,
    required DateTime startedAt,
    required int startLevel,
    required int endLevel,
    required int trials,
    required int correct,
  }) async {
    await requireConsent(patientId, 'gameplay');
    await _db.insert('sessions', {
        'id': _uuid.v4(),
        'patient_id': patientId,
        'game': game,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': _now(),
        'start_level': startLevel,
        'end_level': endLevel,
        'trials': trials,
        'correct': correct,
      });
  }

  /// Local end times of all sessions, for streaks and weekly activity.
  Future<List<DateTime>> sessionTimes(String patientId) async {
    final rows = await _db.query('sessions',
        columns: ['ended_at'], where: 'patient_id = ?', whereArgs: [patientId]);
    return rows
        .map((r) => DateTime.parse(r['ended_at'] as String).toLocal())
        .toList();
  }

  Future<void> setVoiceEnabled(String patientId, bool on, String by) async {
    await _db.update('patients', {'voice_enabled': on ? 1 : 0},
        where: 'id = ?', whereArgs: [patientId]);
    await audit(by, 'voice_${on ? 'enabled' : 'disabled'}', 'patient=$patientId');
  }

  Future<void> setLanguage(String patientId, String language, String by) async {
    await _db.update('patients', {'language': language},
        where: 'id = ?', whereArgs: [patientId]);
    await audit(by, 'language_changed', 'patient=$patientId lang=$language');
  }

  Future<List<int>> recentEndLevels(String patientId, {int limit = 5}) async {
    final rows = await _db.query('sessions',
        columns: ['end_level'],
        where: 'patient_id = ?',
        whereArgs: [patientId],
        orderBy: 'ended_at DESC',
        limit: limit);
    return rows.map((r) => r['end_level'] as int).toList().reversed.toList();
  }

  // ---- sync queue --------------------------------------------------------

  /// Nothing leaves the device without the 'sync' purpose being consented.
  Future<List<Map<String, Object?>>> unsyncedSessions(String patientId) async {
    if (!await hasConsent(patientId, 'sync')) return const [];
    return _db.query('sessions',
        where: 'synced = 0 AND patient_id = ?', whereArgs: [patientId]);
  }

  Future<void> markSessionsSynced(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update('sessions', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // ---- DPDP rights -------------------------------------------------------

  /// Right of access: everything held about the patient.
  Future<Map<String, Object?>> exportPatient(
      String patientId, String requestedBy) async {
    Future<List<Map<String, Object?>>> rows(String table, String where,
            [String? arg]) async =>
        [
          for (final r in await _db
              .query(table, where: where, whereArgs: [arg ?? patientId]))
            _withoutBlobs(r)
        ];
    final patient = await rows('patients', 'id = ?');
    final accountId =
        patient.isEmpty ? null : patient.first['account_id'] as String?;
    final out = {
      'account': accountId == null ? [] : await rows('accounts', 'id = ?', accountId),
      'patient': patient,
      'consents': await rows('consents', 'patient_id = ?'),
      'sessions': await rows('sessions', 'patient_id = ?'),
      'reminders': await rows('reminders', 'patient_id = ?'),
      'family_members': await rows('family_members', 'patient_id = ?'),
      'care_links': await rows('care_links', 'patient_id = ?'),
    };
    await audit(requestedBy, 'patient_exported', 'patient=$patientId');
    return out;
  }

  /// Photos are reported as a size, not dumped as raw bytes.
  Map<String, Object?> _withoutBlobs(Map<String, Object?> row) => {
        for (final e in row.entries)
          e.key: e.value is List<int>
              ? '<photo: ${(e.value as List<int>).length} bytes>'
              : e.value
      };

  /// Right of erasure: removes the patient, everything linked to them and the
  /// login account. The audit log keeps only the fact that erasure happened.
  Future<void> erasePatient(String patientId, String requestedBy) async {
    final p = await _db.query('patients',
        columns: ['account_id'], where: 'id = ?', whereArgs: [patientId]);
    final accountId = p.isEmpty ? null : p.first['account_id'] as String?;
    for (final t in [
      'sessions',
      'reminders',
      'consents',
      'family_members',
      'care_links'
    ]) {
      await _db.delete(t, where: 'patient_id = ?', whereArgs: [patientId]);
    }
    await _db.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    if (accountId != null) {
      await _db.delete('accounts', where: 'id = ?', whereArgs: [accountId]);
    }
    await audit(requestedBy, 'patient_erased',
        'patient=$patientId account=${accountId ?? '-'}');
  }
}
