import '../core/adherence.dart';
import '../core/companion_offline.dart';
import '../core/strings.dart';
import '../data/app_database.dart';
import 'api_client.dart';

class ChatTurn {
  ChatTurn(this.fromUser, this.text, {DateTime? at, this.id})
      : at = at ?? DateTime.now();
  final bool fromUser;
  final String text;
  final DateTime at;

  /// Row id in the local history (null until saved).
  final int? id;
}

class CompanionReply {
  const CompanionReply(this.text,
      {this.emergency = false, this.offline = false, this.why});
  final String text;

  /// When the online helper could not answer, the technical reason (for example
  /// "503 companion_unavailable" or "profile not saved online yet"), so it can be
  /// read out and fixed instead of guessed at. Null when the answer is fine.
  final String? why;

  /// Show the call buttons.
  final bool emergency;

  /// The AI service was wanted but not used (no internet, limit, outage).
  final bool offline;
}

/// 'Talk to Smriti'. Emergencies are answered on the phone with fixed text and
/// never leave it. With the 'companion' consent and a signed-in server account,
/// other messages go to the server's AI companion; otherwise (or if that fails)
/// the on-device helper answers. The conversation is kept on the phone only (encrypted); the server
/// receives just the last few lines as context and stores none of it.
class CompanionService {
  CompanionService({required this.db, this.api, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final ApiClient? api;
  final DateTime Function() _clock;

  /// Sends an AI answer the person flagged to the operator for review (Google Play's
  /// AI-content policy). False when there is no connection.
  Future<bool> reportAnswer(String text) async {
    if (api == null) return false;
    try {
      await api!.reportContent('ai', excerpt: text, reason: 'flagged by user');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The server's id for this patient, once the app has synced at least once.
  Future<String?> _serverId(String patientId) async =>
      (await db.patientById(patientId))?['server_patient_id'] as String?;

  Future<bool> onlineAllowed(String patientId) async =>
      api != null &&
      await api!.hasSession &&
      await _serverId(patientId) != null &&
      await db.hasConsent(patientId, 'companion');

  /// True when the server could be used if the person agreed.
  Future<bool> onlinePossible() async => api != null && await api!.hasSession;

  Future<CompanionReply> day(String lang) async =>
      CompanionReply(dayAnswer(lang, _clock()));

  Future<CompanionReply> next(String patientId, String lang) async {
    final reminders = await db.listReminders(patientId);
    final done = await db.doneKeys(patientId, days: 2);
    return CompanionReply(nextAnswer(lang, reminders, done, _clock()));
  }

  CompanionReply nice(String lang) =>
      CompanionReply(niceThing(lang, _clock().millisecondsSinceEpoch ~/ 1000));

  Future<CompanionReply> ask({
    required String patientId,
    required String lang,
    required String firstName,
    required List<ChatTurn> history,
    required String text,
    Future<void> Function()? syncNow,
  }) async {
    if (isEmergencyText(text, lang)) {
      return CompanionReply(emergencyTextFor(text, lang), emergency: true);
    }
    if (!await onlineAllowed(patientId)) {
      // Signed in only on this phone (an account made before the service existed).
      if (api != null && !await api!.hasSession) {
        return CompanionReply(tr(lang, 'chatNeedsLogin'), why: 'not signed in to the online service');
      }
      if (api == null) return CompanionReply(tr(lang, 'chatOfflineHelp'));
      // Signed in and the person has agreed, but the profile or the consent has not
      // reached the server yet (the usual reason the AI "does not answer"): send
      // them now, once, and carry on if that worked.
      final agreed = await db.hasConsent(patientId, 'companion');
      if (agreed && syncNow != null) {
        try {
          await syncNow();
        } catch (_) {}
      }
      if (!await onlineAllowed(patientId)) {
        return CompanionReply(tr(lang, 'chatOfflineHelp'),
            why: !agreed
                ? 'online helper not allowed yet (tap Allow)'
                : (await _serverId(patientId)) == null
                    ? 'profile not saved online yet (sync failed)'
                    : 'consent not sent yet');
      }
    }
    return _askServer(patientId, lang, firstName, history, text, syncNow, retried: false);
  }

  Future<CompanionReply> _askServer(String patientId, String lang, String firstName,
      List<ChatTurn> history, String text, Future<void> Function()? syncNow,
      {required bool retried}) async {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final reminders = await db.listReminders(patientId);
    final done = await db.doneKeys(patientId, days: 2);
    try {
      final out = await api!.companionChat(
        (await _serverId(patientId))!,
        messages: [
          for (final t in history.skip(history.length > 20 ? history.length - 20 : 0))
            {'role': t.fromUser ? 'user' : 'assistant', 'content': t.text},
          {'role': 'user', 'content': text},
        ],
        lang: lang,
        firstName: firstName,
        nowText: dayAnswer('en', now),
        today: [
          for (final r in reminders)
            if (occursOn(r, today))
              {
                'kind': r.kind.name,
                'time':
                    '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}',
                'done': done.contains(doneKey(r.id, today)),
              }
        ],
      );
      return CompanionReply(out['reply'] as String,
          emergency: out['emergency'] == true);
    } on ApiException catch (e) {
      // The server has not seen the consent yet: send it and ask once more.
      if (e.status == 403 && e.detail == 'consent_required' && !retried && syncNow != null) {
        try {
          await syncNow();
        } catch (_) {}
        return _askServer(patientId, lang, firstName, history, text, syncNow, retried: true);
      }
      final why = e.isNetwork ? 'no connection to the service' : '${e.status} ${e.detail}';
      // Say what is actually wrong, so it can be fixed.
      if (e.status == 503 && e.detail == 'ai_not_configured') {
        return CompanionReply(tr(lang, 'chatAiNotOn'), why: why);
      }
      if (e.status == 429) return CompanionReply(tr(lang, 'chatDailyLimit'), why: why);
      if (e.status == 401) return CompanionReply(tr(lang, 'chatNeedsLogin'), why: why);
      // 503 companion_unavailable (the service failed: quota, bad key, outage) and
      // anything else: the on-device helper answers and the reason is shown.
      return CompanionReply(tr(lang, 'chatOfflineHelp'), offline: true, why: why);
    }
  }
}
