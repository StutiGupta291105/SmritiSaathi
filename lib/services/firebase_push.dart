import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/config.dart';
import '../core/notify_text.dart';
import '../core/strings.dart';
import '../data/app_database.dart';
import '../data/session_store.dart';
import 'api_client.dart';
import 'push_events.dart';
import 'push_service.dart';
import 'reminder_notifier.dart';
import 'sync_service.dart';

/// Gets this phone's Firebase push token. Without a Firebase project in the
/// build (no `google-services.json`) `Firebase.initializeApp()` throws; that is
/// caught and the app simply runs without background push, as before.
class FirebasePushSource implements PushTokenSource {
  const FirebasePushSource();

  @override
  Future<String?> token() async {
    try {
      await Firebase.initializeApp();
      final m = FirebaseMessaging.instance;
      // The notification permission is asked once, on the Permissions screen; asking for a
      // push token needs no prompt.
      return await m.getToken();
    } catch (_) {
      return null;
    }
  }
}

/// Runs when a data-only push arrives while the app is closed or in the
/// background (Android). For "your routine was updated" it fetches the change,
/// schedules the new alarms on the phone right away, and shows the generic
/// notification itself, so the patient does not have to open the app first.
/// Must be a top-level function (it runs in its own isolate).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final open = PushOpen.fromData(message.data);
  if (open == null || open.type != 'routine') return;
  AppDatabase? db;
  try {
    await Firebase.initializeApp();
    db = await AppDatabase.open();
    final accountId = await const SessionStore().read();
    final account = accountId == null ? null : await db.accountById(accountId);
    if (account == null || account['role'] != 'patient') return;
    final patient = await db.patientForAccount(account['id'] as String);
    if (patient == null || (patient['setup_stage'] as int) < 5) return;
    final pid = patient['id'] as String;
    final lang = patient['language'] as String;
    final notifier = ReminderNotifier(db);
    await notifier.initBackground();
    if (kOnlineConfigured) {
      final api = ApiClient(baseUrl: kApiBaseUrl, store: db);
      if (await api.hasSession) {
        try {
          await SyncService(db, api).run(pid);
        } catch (_) {
          // Offline or the service is asleep: the app syncs at its next start.
        }
      }
    }
    await notifier.resync(patientId: pid, lang: lang);
    await notifier.showNow(tr(lang, 'appName'), notifyText(lang, 'routineUpdated'),
        payload: 'routine');
  } catch (_) {
    // Best effort: the app syncs again the next time it is opened.
  } finally {
    await db?.close();
  }
}

/// Foreground push events: a routine changed while the app is open, and taps on
/// a push that was shown by the system.
class PushEvents {
  static bool _started = false;

  static Future<void> start({required void Function() onRoutineChanged}) async {
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'routine') onRoutineChanged();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final open = PushOpen.fromData(m.data);
        if (open != null) kPushOpen.value = open;
      });
      final first = await FirebaseMessaging.instance.getInitialMessage();
      final open = first == null ? null : PushOpen.fromData(first.data);
      if (open != null) kPushOpen.value = open;
    } catch (_) {
      // No Firebase project in this build: nothing to listen to.
    }
  }
}
