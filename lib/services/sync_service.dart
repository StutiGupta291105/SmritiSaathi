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

  static const _serverRole = {'doctor': 'doctor', 'caregiver': 'caretaker'};

  Future<SyncOutcome> run(String patientId) async {
    try {
      final patient = await db.patientById(patientId);
      if (patient == null) return SyncOutcome.failed;

      var serverId = patient['server_patient_id'] as String?;
      if (serverId == null) {
        final created = await api.createPatient(
          displayName: patient['display_name'] as String,
          language: patient['language'] as String,
          baselineLevel: patient['baseline_level'] as int,
          tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        );
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
          final out = await api.createInvite(
            serverId,
            role: _serverRole[inv['kind']] ?? 'caretaker',
            phoneE164: inv['phone'] as String,
            name: inv['name'] as String,
            professionalId: inv['professional_id'] as String,
          );
          await db.setCareLinkServerId(inv['id'] as String, out['id'] as String);
        } on ApiException catch (e) {
          // 403: consent for this kind of sharing is not given; leave it queued.
          if (e.isNetwork || e.isUnauthorized) rethrow;
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

      await db.applyServerLinkStatuses(patientId, await api.links(serverId));
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
  const ServerHooks({required this.syncNow, required this.eraseRemote});

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
