import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

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
      await m.requestPermission();
      return await m.getToken();
    } catch (_) {
      return null;
    }
  }
}
