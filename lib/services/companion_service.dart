import '../core/adherence.dart';
import '../core/companion_offline.dart';
import '../core/strings.dart';
import '../data/app_database.dart';
import 'api_client.dart';

class ChatTurn {
  const ChatTurn(this.fromUser, this.text);
  final bool fromUser;
  final String text;
}

class CompanionReply {
  const CompanionReply(this.text, {this.emergency = false, this.offline = false});
  final String text;

  /// Show the call buttons.
  final bool emergency;

  /// The AI service was wanted but not used (no internet, limit, outage).
  final bool offline;
}

/// 'Talk to Smriti'. Emergencies are answered on the phone with fixed text and
/// never leave it. With the 'companion' consent and a signed-in server account,
/// other messages go to the server's AI companion; otherwise (or if that fails)
/// the on-device helper answers. Chat history lives in memory only.
class CompanionService {
  CompanionService({required this.db, this.api, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final ApiClient? api;
  final DateTime Function() _clock;

  Future<bool> onlineAllowed(String patientId) async =>
      api != null &&
      await api!.hasSession &&
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
  }) async {
    if (isEmergencyText(text, lang)) {
      return CompanionReply(emergencyText(lang), emergency: true);
    }
    if (!await onlineAllowed(patientId)) {
      return CompanionReply(tr(lang, 'chatOfflineHelp'));
    }
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final reminders = await db.listReminders(patientId);
    final done = await db.doneKeys(patientId, days: 2);
    try {
      final out = await api!.companionChat(
        patientId,
        messages: [
          for (final t in history.take(history.length))
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
    } on ApiException {
      return CompanionReply(tr(lang, 'chatOfflineHelp'), offline: true);
    }
  }
}
