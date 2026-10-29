import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/ability_model.dart';
import '../core/adherence.dart';
import '../core/adaptive_engine.dart';
import '../core/engagement_alerts.dart';
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
  'companion',
];

enum PinResult { ok, wrong, locked }

/// What is waiting to be uploaded.
class SyncBatch {
  SyncBatch(this.sessions, this.schedules, this.marks);
  final List<Map<String, Object?>> sessions, schedules, marks;

  bool get isEmpty => sessions.isEmpty && schedules.isEmpty && marks.isEmpty;
}

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
  AppDatabase._(this._db) : _clock = DateTime.now;
  final Database _db;
  final DateTime Function() _clock;
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

  static const schemaVersion = 7;

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
        caregiver_pin_hash TEXT,
        caregiver_pin_salt TEXT,
        server_patient_id TEXT,
        server_baseline INTEGER,
        email TEXT,
        city TEXT,
        state TEXT,
        created_at TEXT NOT NULL
      )''');
    await _createAccountTables(db);
    await _createReminderLog(db);
    await db.execute('''
      CREATE TABLE consents(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        purpose TEXT NOT NULL,
        granted INTEGER NOT NULL,
        given_by_name TEXT NOT NULL,
        given_by_relation TEXT NOT NULL,   -- 'self' or guardian relationship
        notice_version TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
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
        level_stats TEXT,
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
    if (oldVersion < 3) {
      for (final stmt in [
        'ALTER TABLE sessions ADD COLUMN level_stats TEXT',
        'ALTER TABLE patients ADD COLUMN caregiver_pin_hash TEXT',
        'ALTER TABLE patients ADD COLUMN caregiver_pin_salt TEXT',
      ]) {
        await db.execute(stmt);
      }
    }
    if (oldVersion < 4) {
      await _createReminderLog(db);
    }
    if (oldVersion < 5) {
      // Links the app to the server account. Idempotent, because tables made
      // earlier in this same upgrade already have some of these columns.
      await _addColumn(db, 'accounts', 'server_user_id TEXT');
      await _addColumn(db, 'patients', 'server_patient_id TEXT');
      await _addColumn(db, 'consents', 'synced INTEGER NOT NULL DEFAULT 0');
      await _addColumn(db, 'care_links', 'phone TEXT');
      await _addColumn(db, 'care_links', 'server_link_id TEXT');
    }
    if (oldVersion < 6) {
      // Last starting level seen on the server, and whether an operator checked
      // a doctor's registration.
      await _addColumn(db, 'patients', 'server_baseline INTEGER');
      await _addColumn(db, 'care_links', 'verified INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      // Profile details from the single-form profile page. Kept on the phone;
      // they are not part of what is synced to the server.
      await _addColumn(db, 'patients', 'email TEXT');
      await _addColumn(db, 'patients', 'city TEXT');
      await _addColumn(db, 'patients', 'state TEXT');
    }
  }

  static Future<void> _addColumn(Database db, String table, String def) async {
    final name = def.split(' ').first;
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.isEmpty) return; // table not present in this upgrade path
    if (cols.any((c) => c['name'] == name)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $def');
  }

  /// For tests: wraps an already-open database (for example in-memory SQLite).
  @visibleForTesting
  AppDatabase.forTesting(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static Future<void> _createReminderLog(Database db) async {
    // One row per reminder per day that was marked done. Holds no reminder text.
    await db.execute('''
      CREATE TABLE reminder_log(
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        reminder_id TEXT NOT NULL,
        day TEXT NOT NULL,
        marked_at TEXT NOT NULL,
        UNIQUE(reminder_id, day)
      )''');
  }

  static Future<void> _createAccountTables(Database db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id TEXT PRIMARY KEY,
        phone TEXT NOT NULL,
        role TEXT NOT NULL,
        name TEXT NOT NULL,
        server_user_id TEXT,
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
        phone TEXT,
        server_link_id TEXT,
        verified INTEGER NOT NULL DEFAULT 0,
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

  Future<Map<String, Object?>?> patientById(String id) async {
    final rows =
        await _db.query('patients', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
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
    String? displayName,
    String? email,
    String? city,
    String? state,
    required String by,
  }) async {
    final values = <String, Object?>{};
    if (displayName != null && displayName.trim().isNotEmpty) {
      values['display_name'] = displayName.trim();
    }
    if (email != null) values['email'] = email.trim().isEmpty ? null : email.trim();
    if (city != null) values['city'] = city.trim().isEmpty ? null : city.trim();
    if (state != null) values['state'] = state.trim().isEmpty ? null : state.trim();
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
  /// 0 about you, 1 family, 2 doctor, 3 caregiver, 4 routine, 5 done.
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
    String? phone,
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
      'phone': phone,
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
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal(),
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
    String? levelStats,
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
        'level_stats': levelStats,
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

  // ---- restore on a new phone --------------------------------------------

  static const _linkKindFromServer = {'caretaker': 'caregiver', 'doctor': 'doctor'};

  /// Rebuilds a patient from the server's snapshot after sign-in on a new
  /// phone. Everything in it was shared with consent before, so it is written
  /// directly and marked as already synced. Photos, family, reminder text and
  /// the caregiver PIN were never uploaded and have to be set up again, so the
  /// profile flow starts from its first step. Returns the new local patient id.
  Future<String> restoreFromSnapshot({
    required String accountId,
    required String phone,
    required Map<String, dynamic> snapshot,
  }) async {
    final pt = snapshot['patient'] as Map<String, dynamic>;
    final id = _uuid.v4();
    List<Map<String, dynamic>> list(String k) =>
        ((snapshot[k] as List?) ?? const []).cast<Map<String, dynamic>>();

    await _db.transaction((txn) async {
      await txn.insert('patients', {
        'id': id,
        'account_id': accountId,
        'phone': phone,
        'display_name': pt['display_name'],
        'language': pt['language'],
        'baseline_level': pt['baseline_level'],
        'setup_stage': 0,
        'server_patient_id': pt['id'],
        'server_baseline': pt['baseline_level'],
        'created_at': _now(),
      });
      for (final c in list('consents')) {
        await txn.insert('consents', {
          'id': _uuid.v4(),
          'patient_id': id,
          'purpose': c['purpose'],
          'granted': c['granted'] == true ? 1 : 0,
          'given_by_name': c['given_by_name'],
          'given_by_relation': c['given_by_relation'],
          'notice_version': c['notice_version'],
          'synced': 1,
          'created_at': c['created_at'],
        });
      }
      for (final s in list('sessions')) {
        await txn.insert('sessions', {
          'id': s['id'],
          'patient_id': id,
          'game': s['game'],
          'started_at': s['started_at'],
          'ended_at': s['ended_at'],
          'start_level': s['start_level'],
          'end_level': s['end_level'],
          'trials': s['trials'],
          'correct': s['correct'],
          'level_stats': s['level_stats'],
          'synced': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final r in list('schedules')) {
        await txn.insert('reminders', {
          'id': r['id'],
          'patient_id': id,
          'kind': r['kind'],
          'label': '', // reminder text never left the phone
          'hour': r['hour'],
          'minute': r['minute'],
          'days_mask': r['days_mask'],
          'on_date': r['on_date'],
          'active': r['active'] == true ? 1 : 0,
          'created_by': 'restore',
          'created_at': r['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final m in list('marks')) {
        await txn.insert('reminder_log', {
          'id': _uuid.v4(),
          'patient_id': id,
          'reminder_id': m['reminder_id'],
          'day': m['day'],
          'marked_at': m['marked_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final l in list('links')) {
        await txn.insert('care_links', {
          'id': _uuid.v4(),
          'patient_id': id,
          'kind': _linkKindFromServer[l['kind']] ?? 'caregiver',
          'name': l['name'],
          'professional_id': l['professional_id'] ?? '',
          'server_link_id': l['id'],
          'status': l['status'],
          'created_at': _now(),
        });
      }
    });
    await audit('restore', 'patient_restored',
        'patient=$id sessions=${list('sessions').length} reminders=${list('schedules').length}');
    return id;
  }

  // ---- link to the server ------------------------------------------------
  // The app is offline-first: everything is saved here first. These methods
  // track what the server already has, so nothing is sent twice and nothing is
  // sent without the matching consent.

  Future<void> linkServerAccount(String accountId, String serverUserId) =>
      _db.update('accounts', {'server_user_id': serverUserId},
          where: 'id = ?', whereArgs: [accountId]);

  Future<Map<String, Object?>?> accountByServerId(String serverUserId) async {
    final rows = await _db.query('accounts',
        where: 'server_user_id = ?', whereArgs: [serverUserId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setServerPatientId(String patientId, String serverId) =>
      _db.update('patients', {'server_patient_id': serverId},
          where: 'id = ?', whereArgs: [patientId]);

  /// Consent decisions the server has not seen yet, oldest first. Consent
  /// records must reach the server even after withdrawal, so that sharing
  /// stops there too.
  Future<List<Map<String, Object?>>> unsyncedConsents(String patientId) =>
      _db.query('consents',
          where: 'patient_id = ? AND synced = 0',
          whereArgs: [patientId],
          orderBy: 'rowid');

  Future<void> markConsentsSynced(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update('consents', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Game results not yet uploaded (only with 'sync' and 'gameplay'), and the
  /// timing of reminders and their done marks (only with 'sync' and
  /// 'reminders'). Reminder text such as medicine names is never included.
  Future<SyncBatch> syncBatch(String patientId, {int markDays = 120}) async {
    final empty = SyncBatch(const [], const [], const []);
    if (!await hasConsent(patientId, 'sync')) return empty;

    var sessions = <Map<String, Object?>>[];
    if (await hasConsent(patientId, 'gameplay')) {
      for (final r in await _db.query('sessions',
          where: 'synced = 0 AND patient_id = ?', whereArgs: [patientId])) {
        sessions.add({
          'id': r['id'],
          'game': r['game'],
          'started_at': r['started_at'],
          'ended_at': r['ended_at'],
          'start_level': r['start_level'],
          'end_level': r['end_level'],
          'trials': r['trials'],
          'correct': r['correct'],
          'level_stats': r['level_stats'],
        });
      }
    }

    final schedules = <Map<String, Object?>>[];
    final marks = <Map<String, Object?>>[];
    if (await hasConsent(patientId, 'reminders')) {
      for (final r in await _db.query('reminders',
          where: 'patient_id = ?', whereArgs: [patientId])) {
        final onDate = r['on_date'] as String?;
        schedules.add({
          'id': r['id'],
          'kind': r['kind'],
          'hour': r['hour'],
          'minute': r['minute'],
          'days_mask': r['days_mask'],
          'on_date': onDate?.substring(0, 10),
          'active': r['active'] == 1,
          'created_at': r['created_at'],
        });
      }
      final since = doneKey('x', DateTime.now().subtract(Duration(days: markDays)))
          .split('|')
          .last;
      for (final r in await _db.query('reminder_log',
          where: 'patient_id = ? AND day >= ?', whereArgs: [patientId, since])) {
        marks.add({
          'reminder_id': r['reminder_id'],
          'day': r['day'],
          'marked_at': r['marked_at'],
        });
      }
    }
    return SyncBatch(sessions, schedules, marks);
  }

  /// Invites that were saved offline and still need sending.
  Future<List<Map<String, Object?>>> unsentInvites(String patientId) =>
      _db.query('care_links',
          where:
              "patient_id = ? AND server_link_id IS NULL AND phone IS NOT NULL AND status = 'pending'",
          whereArgs: [patientId],
          orderBy: 'rowid');

  Future<void> setCareLinkServerId(String linkId, String serverLinkId) =>
      _db.update('care_links', {'server_link_id': serverLinkId},
          where: 'id = ?', whereArgs: [linkId]);

  /// The starting level on the server changed (a caretaker set it). Recorded
  /// like any other baseline change, attributed to the server.
  Future<void> applyServerBaseline(String patientId, int level) async {
    await setBaseline(
        patientId: patientId,
        newLevel: level,
        caregiverName: 'caretaker (online)',
        reason: 'changed online');
    await setServerBaseline(patientId, level);
  }

  Future<void> setServerBaseline(String patientId, int level) =>
      _db.update('patients', {'server_baseline': level},
          where: 'id = ?', whereArgs: [patientId]);

  /// Applies the server's view of each invite (accepted, declined, revoked).
  Future<void> applyServerLinkStatuses(
      String patientId, List<Map<String, dynamic>> serverLinks) async {
    for (final l in serverLinks) {
      await _db.update('care_links',
          {'status': l['status'], 'verified': l['verified'] == true ? 1 : 0},
          where: 'server_link_id = ? AND patient_id = ?',
          whereArgs: [l['id'], patientId]);
    }
  }

  // ---- reminder completion -----------------------------------------------

  /// Marks a reminder done (or undoes it) for [day]. Covered by the 'reminders'
  /// purpose. The log stores the reminder id and the day only.
  Future<void> setReminderDone({
    required String patientId,
    required String reminderId,
    required DateTime day,
    required bool done,
    required String by,
  }) async {
    await requireConsent(patientId, 'reminders');
    final key = doneKey(reminderId, day).split('|').last;
    if (done) {
      await _db.insert(
          'reminder_log',
          {
            'id': _uuid.v4(),
            'patient_id': patientId,
            'reminder_id': reminderId,
            'day': key,
            'marked_at': _now(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.delete('reminder_log',
          where: 'reminder_id = ? AND day = ?', whereArgs: [reminderId, key]);
    }
    await audit(by, done ? 'reminder_marked_done' : 'reminder_unmarked',
        'patient=$patientId reminder=$reminderId');
  }

  /// Keys (see [doneKey]) of everything marked done in the last [days] days.
  Future<Set<String>> doneKeys(String patientId, {int days = 100}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await _db.query('reminder_log',
        where: 'patient_id = ? AND day >= ?',
        whereArgs: [
          patientId,
          doneKey('x', since).split('|').last,
        ]);
    return {
      for (final r in rows) '${r['reminder_id']}|${r['day']}',
    };
  }

  // ---- caregiver dashboard data ------------------------------------------

  Future<List<SessionRecord>> sessionRecords(String patientId) async {
    final rows = await _db.query('sessions',
        where: 'patient_id = ?', whereArgs: [patientId], orderBy: 'ended_at');
    return [
      for (final r in rows)
        SessionRecord(
          game: r['game'] as String,
          endedAt: DateTime.parse(r['ended_at'] as String).toLocal(),
          startLevel: r['start_level'] as int,
          endLevel: r['end_level'] as int,
          trials: r['trials'] as int,
          correct: r['correct'] as int,
        )
    ];
  }

  /// Per-level tallies from the most recent sessions of [game], for the
  /// ability model. Sessions saved before level tallies existed are skipped.
  Future<List<LevelStat>> levelStats(String patientId, String game,
      {int lastSessions = 40}) async {
    final rows = await _db.query('sessions',
        columns: ['level_stats'],
        where: 'patient_id = ? AND game = ? AND level_stats IS NOT NULL',
        whereArgs: [patientId, game],
        orderBy: 'ended_at DESC',
        limit: lastSessions);
    final totals = <int, List<int>>{};
    for (final r in rows) {
      final decoded = jsonDecode(r['level_stats'] as String) as Map;
      decoded.forEach((level, v) {
        final t = totals.putIfAbsent(int.parse('$level'), () => [0, 0]);
        t[0] += (v as List)[0] as int;
        t[1] += v[1] as int;
      });
    }
    return [
      for (final e in totals.entries) LevelStat(e.key, e.value[0], e.value[1])
    ];
  }

  /// The learned model for one game (see [AbilityModel]).
  Future<AbilityModel> abilityModel(
          String patientId, String game, int baseline) async =>
      AbilityModel.fit(
          stats: await levelStats(patientId, game), baseline: baseline);

  /// Level a game should start at: the model's pick inside the caregiver's band.
  Future<int> recommendedStartLevel(
      String patientId, String game, int baseline) async {
    final model = await abilityModel(patientId, game, baseline);
    return model.recommend(DifficultyBand(baseline));
  }

  /// Alerts for the patient right now, or none when sharing with the caregiver
  /// is not consented. Used for the badge on the Caregiver area entry.
  Future<List<EngagementAlert>> currentAlerts(String patientId) async {
    if (!await hasConsent(patientId, 'caregiver_share')) return const [];
    final patient = await patientById(patientId);
    if (patient == null) return const [];
    final reminders = await listReminders(patientId);
    final done = await doneKeys(patientId);
    final now = DateTime.now();
    return computeAlerts(
      sessions: await sessionRecords(patientId),
      now: now,
      baseline: patient['baseline_level'] as int,
      overdueMedicines: overdueMedicines(reminders, done, now).length,
      weekAdherence: adherence(reminders, done, now),
    );
  }

  // ---- caregiver PIN -------------------------------------------------------

  static const _pinRounds = 10000;
  static const maxPinTries = 5;
  static const pinLockMinutes = 15;
  final Map<String, int> _pinFailures = {};
  final Map<String, DateTime> _pinLockedUntil = {};

  static String _hashPin(String pin, String salt) {
    List<int> h = utf8.encode('$salt:$pin');
    for (var i = 0; i < _pinRounds; i++) {
      h = sha256.convert(h).bytes;
    }
    return base64UrlEncode(h);
  }

  Future<bool> hasCaregiverPin(String patientId) async {
    final r = await _db.query('patients',
        columns: ['caregiver_pin_hash'],
        where: 'id = ?',
        whereArgs: [patientId]);
    return r.isNotEmpty && r.first['caregiver_pin_hash'] != null;
  }

  /// The PIN guards the caregiver area on a phone the patient also holds. It
  /// is stored salted and hashed, never in the clear.
  Future<void> setCaregiverPin(String patientId, String pin, String by) async {
    final rnd = Random.secure();
    final salt = base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _db.update(
        'patients',
        {'caregiver_pin_salt': salt, 'caregiver_pin_hash': _hashPin(pin, salt)},
        where: 'id = ?',
        whereArgs: [patientId]);
    await audit(by, 'caregiver_pin_set', 'patient=$patientId');
  }

  /// Wrong tries are counted; after [maxPinTries] the area is locked for
  /// [pinLockMinutes] minutes. Every outcome is audited.
  Future<PinResult> verifyCaregiverPin(
      String patientId, String pin, String by) async {
    final until = _pinLockedUntil[patientId];
    if (until != null) {
      if (_clock().isBefore(until)) return PinResult.locked;
      _pinLockedUntil.remove(patientId);
      _pinFailures.remove(patientId);
    }
    final r = await _db.query('patients',
        columns: ['caregiver_pin_hash', 'caregiver_pin_salt'],
        where: 'id = ?',
        whereArgs: [patientId]);
    if (r.isEmpty || r.first['caregiver_pin_hash'] == null) {
      return PinResult.wrong;
    }
    final ok = _hashPin(pin, r.first['caregiver_pin_salt'] as String) ==
        r.first['caregiver_pin_hash'];
    if (ok) {
      _pinFailures.remove(patientId);
      await audit(by, 'caregiver_area_opened', 'patient=$patientId');
      return PinResult.ok;
    }
    final n = (_pinFailures[patientId] ?? 0) + 1;
    _pinFailures[patientId] = n;
    await audit(by, 'caregiver_pin_failed', 'patient=$patientId tries=$n');
    if (n >= maxPinTries) {
      _pinLockedUntil[patientId] =
          _clock().add(const Duration(minutes: pinLockMinutes));
      return PinResult.locked;
    }
    return PinResult.wrong;
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
      'reminder_log': await rows('reminder_log', 'patient_id = ?'),
    };
    await audit(requestedBy, 'patient_exported', 'patient=$patientId');
    return out;
  }

  /// Photos are reported as a size, not dumped as raw bytes.
  Map<String, Object?> _withoutBlobs(Map<String, Object?> row) => {
        for (final e in row.entries)
          if (e.key != 'caregiver_pin_hash' && e.key != 'caregiver_pin_salt')
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
      'care_links',
      'reminder_log'
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
