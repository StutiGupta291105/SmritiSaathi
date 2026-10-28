import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

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
            synced INTEGER NOT NULL DEFAULT 0
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

  Future<void> audit(String actor, String action, String detail) =>
      _db.insert('audit_log', {
        'id': _uuid.v4(),
        'ts': _now(),
        'actor': actor,
        'action': action,
        'detail': detail,
      });

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
        orderBy: 'created_at DESC',
        limit: 1);
    return rows.isNotEmpty && rows.first['granted'] == 1;
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
  }) =>
      _db.insert('sessions', {
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

  Future<List<Map<String, Object?>>> unsyncedSessions() =>
      _db.query('sessions', where: 'synced = 0');

  Future<void> markSessionsSynced(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update('sessions', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // ---- DPDP rights -------------------------------------------------------

  /// Right of access: everything held about the patient.
  Future<Map<String, Object?>> exportPatient(String patientId) async => {
        'patient': await _db
            .query('patients', where: 'id = ?', whereArgs: [patientId]),
        'consents': await _db
            .query('consents', where: 'patient_id = ?', whereArgs: [patientId]),
        'sessions': await _db
            .query('sessions', where: 'patient_id = ?', whereArgs: [patientId]),
      };

  /// Right of erasure. The audit log keeps only the fact that erasure happened.
  Future<void> erasePatient(String patientId, String requestedBy) async {
    await _db.delete('sessions', where: 'patient_id = ?', whereArgs: [patientId]);
    await _db.delete('consents', where: 'patient_id = ?', whereArgs: [patientId]);
    await _db.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    await audit(requestedBy, 'patient_erased', 'patient=$patientId');
  }
}
