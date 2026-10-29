import 'dart:io' show Platform;

import 'api_client.dart';

/// Where a phone's push token comes from. The Firebase plugin is not part of
/// the build yet (it needs your Firebase project's `google-services.json`), so
/// the app ships [NoPush]. To turn push on: add `firebase_messaging`, write a
/// `PushTokenSource` that returns `FirebaseMessaging.instance.getToken()`, and
/// pass it to [PushRegistrar] in `main.dart`.
abstract class PushTokenSource {
  Future<String?> token();
}

class NoPush implements PushTokenSource {
  const NoPush();
  @override
  Future<String?> token() async => null;
}

/// Tells the server which phone to notify for the signed-in account, and
/// forgets it on sign-out so the next person on a shared phone gets nothing
/// meant for the previous one. Best effort: push is never needed to use the app.
class PushRegistrar {
  PushRegistrar(this.api, this.source, {TokenStore? store, String? platform})
      : _store = store ?? const SecureTokenStore(),
        _platform = platform ?? (Platform.isIOS ? 'ios' : 'android');
  final ApiClient api;
  final PushTokenSource source;
  final TokenStore _store;
  final String _platform;

  static const _key = 'push_token';

  Future<void> register() async {
    try {
      final t = await source.token();
      if (t == null || t.length < 20) return;
      await api.registerDevice(t, _platform);
      await _store.write(_key, t);
    } on ApiException {
      // Try again at the next sign-in or app start.
    }
  }

  Future<void> unregister() async {
    final t = await _store.read(_key);
    if (t == null) return;
    try {
      await api.unregisterDevice(t, _platform);
    } on ApiException {
      // The server drops dead tokens by itself.
    }
    await _store.delete(_key);
  }
}
