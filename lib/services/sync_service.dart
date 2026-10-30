import '../data/app_database.dart';
import 'api_client.dart';

enum SyncOutcome { done, offline, signedOut, failed }

/// Sends what the patient has agreed to share to the server, in this order:
/// the patient record, consent decisions (always, including withdrawals),
/// invites saved offline, then game results and reminder timing (only with the
/// matching consent). Safe to run repeatedly; everything is idempotent.
class SyncService {
  SyncService(this.db, this.api);
  final AppDatabase db;
  final ApiClient api;

  /// True after [run] when a caregiver or doctor added or removed a routine, so
  /// the phone's notifications need setting up again.
  bool remindersChanged = false;

  static const _serverRole = {'doctor': 'doctor', 'caregiver': 'caretaker'};

  /// Keeps the starting level in step in both directions without either side
  /// overwriting a newer change: a change made on this phone is sent; otherwise
  /// a change made by a caretaker online is applied here. Needs 'sync'.
  Future<void> _syncBaseline(String patientId, String serverId) async {
    if (!await db.hasConsent(patientId, 'sync')) return;
    final patient = (await db.patientById(patientId))!;
    final local = patient['baseline_level'] as int;
    final seen = patient['server_baseline'] as int?;
    final server = (await api.myPatient())['baseline_level'] as int;
    if (seen == null || local != seen) {
      if (server != local) await api.setBaseline(serverId, local);
      await db.setServerBaseline(patientId, local);
    } else if (server != seen) {
      await db.applyServerBaseline(patientId, server);
    }
  }

  Future<SyncOutcome> run(String patientId) async {
    try {
      final patient = await db.patientById(patientId);
      if (patient == null) return SyncOutcome.failed;

      var serverId = patient['server_patient_id'] as String?;
      if (serverId == null) {
        Map<String, dynamic> created;
        try {
          created = await api.createPatient(
            displayName: patient['display_name'] as String,
            language: patient['language'] as String,
            baselineLevel: patient['baseline_level'] as int,
            tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          );
        } on ApiException catch (e) {
          // This login already has a patient on the server (reinstall, or a
          // new phone where the person chose not to restore): carry on with it.
          if (e.status != 409) rethrow;
          created = await api.myPatient();
        }
        serverId = created['id'] as String;
        await db.setServerPatientId(patientId, serverId);
      }

      final consents = await db.unsyncedConsents(patientId);
      if (consents.isNotEmpty) {
        await api.addConsents(serverId, [
          for (final c in consents)
            {
              'purpose': c['purpose'],
              'granted': c['granted'] == 1,
              'given_by_name': c['given_by_name'],
              'given_by_relation': c['given_by_relation'],
              'notice_version': c['notice_version'],
            }
        ]);
        await db.markConsentsSynced([for (final c in consents) c['id'] as String]);
      }

      for (final inv in await db.unsentInvites(patientId)) {
        try {
          // A phone number means an older invite; new ones carry the care ID.
          final phone = inv['phone'] as String?;
          final byPhone = phone != null && phone.isNotEmpty;
          final out = await api.createInvite(
            serverId,
            role: _serverRole[inv['kind']] ?? 'caretaker',
            phoneE164: byPhone ? phone : '',
            careId: byPhone ? '' : inv['professional_id'] as String,
            name: inv['name'] as String,
            professionalId: byPhone ? inv['professional_id'] as String : '',
          );
          await db.setCareLinkServerId(inv['id'] as String, out['id'] as String);
        } on ApiException catch (e) {
          if (e.isNetwork || e.isUnauthorized) rethrow;
          // Nobody has that ID (or it is the wrong kind): the patient is told
          // and can enter another. 403 (no consent yet) stays queued.
          if (e.detail == 'care_id_not_found' ||
              e.detail == 'invalid_care_id' ||
              e.detail == 'care_id_wrong_role') {
            await db.setCareLinkStatus(inv['id'] as String, 'notfound');
          } else if (e.detail == 'already_invited') {
            await db.setCareLinkStatus(inv['id'] as String, 'pending');
          }
        }
      }

      final batch = await db.syncBatch(patientId);
      if (!batch.isEmpty) {
        await api.sync(serverId, {
          'sessions': batch.sessions,
          'schedules': batch.schedules,
          'marks': batch.marks,
        });
        await db.markSessionsSynced(
            [for (final s in batch.sessions) s['id'] as String]);
      }

      await _syncBaseline(patientId, serverId);
      await db.applyServerLinkStatuses(patientId, await api.links(serverId));

      // Routines and reminders a caregiver or doctor set. Deletions made here
      // go first so they are not copied back.
      for (final id in await db.pendingCareReminderDeletes()) {
        try {
          await api.deleteCareReminder(serverId, id);
          await db.clearCareReminderDelete(id);
        } on ApiException catch (e) {
          if (e.isNetwork || e.isUnauthorized) rethrow;
          if (e.status == 404) await db.clearCareReminderDelete(id);
        }
      }
      remindersChanged =
          await db.applyCareReminders(patientId, await api.careReminders(serverId));
      return SyncOutcome.done;
    } on ApiException catch (e) {
      if (e.isNetwork) return SyncOutcome.offline;
      if (e.isUnauthorized) return SyncOutcome.signedOut;
      return SyncOutcome.failed;
    }
  }
}

/// What the screens can ask of the server without knowing about HTTP.
/// Null in builds that have no API address.
class ServerHooks {
  const ServerHooks({required this.syncNow, required this.eraseRemote, this.endLink});

  /// Ends a link on the server so that person no longer sees anything. True
  /// when it is gone (also when it was already), false when it could not be
  /// reached. Null in tests that do not need it.
  final Future<bool> Function(String serverLinkId)? endLink;

  /// Sends pending changes now (e.g. right after a consent was changed).
  final Future<void> Function() syncNow;

  /// Erases this patient's data on the server. True when there is nothing left
  /// there (including when it never held any); false if it could not be
  /// reached, in which case the local erase should not go ahead.
  final Future<bool> Function(String patientId) eraseRemote;
}

ServerHooks serverHooks(AppDatabase db, ApiClient api, Future<void> Function() sync) =>
    ServerHooks(
      syncNow: sync,
      endLink: (serverLinkId) async {
        try {
          await api.revokeLink(serverLinkId);
          return true;
        } on ApiException catch (e) {
          return e.status == 404; // already gone
        }
      },
      eraseRemote: (patientId) async {
        final serverId =
            (await db.patientById(patientId))?['server_patient_id'] as String?;
        if (serverId == null) return true;
        try {
          await api.eraseServerData(serverId);
          return true;
        } on ApiException catch (e) {
          return e.status == 404; // already gone
        }
      },
    );
