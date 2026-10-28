import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE patients(
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            language TEXT NOT NULL DEFAULT 'en',
            baseline_level INTEGER NOT NULL,
            voice_enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )''');
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
      },
    );
    return AppDatabase._(db);
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

  Future<String> createPatient({
    required String displayName,
    required int baselineLevel,
    required String language,
    required String caregiverName,
  }) async {
    final id = _uuid.v4();
    await _db.insert('patients', {
      'id': id,
      'display_name': displayName,
      'language': language,
      'baseline_level': baselineLevel,
      'created_at': _now(),
    });
    await audit(caregiverName, 'patient_created',
        'patient=$id baseline=$baselineLevel');
    return id;
  }

  Future<Map<String, Object?>?> firstPatient() async {
    final rows = await _db.query('patients', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

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
    await audit(byName, 'consent_withdrawn',
        'patient=$patientId relation=$byRelation purpose=$purpose');
  }

  Future<Map<String, bool>> consentState(String patientId) async => {
        for (final purpose in const [
          'gameplay',
          'reminders',
          'caregiver_share',
          'sync'
        ])
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
    final out = {
      'patient': await _db
          .query('patients', where: 'id = ?', whereArgs: [patientId]),
      'consents': await _db
          .query('consents', where: 'patient_id = ?', whereArgs: [patientId]),
      'sessions': await _db
          .query('sessions', where: 'patient_id = ?', whereArgs: [patientId]),
      'reminders': await _db
          .query('reminders', where: 'patient_id = ?', whereArgs: [patientId]),
    };
    await audit(requestedBy, 'patient_exported', 'patient=$patientId');
    return out;
  }

  /// Right of erasure. The audit log keeps only the fact that erasure happened.
  Future<void> erasePatient(String patientId, String requestedBy) async {
    await _db.delete('sessions', where: 'patient_id = ?', whereArgs: [patientId]);
    await _db.delete('reminders', where: 'patient_id = ?', whereArgs: [patientId]);
    await _db.delete('consents', where: 'patient_id = ?', whereArgs: [patientId]);
    await _db.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    await audit(requestedBy, 'patient_erased', 'patient=$patientId');
  }
}
