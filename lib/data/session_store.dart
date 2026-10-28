import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers which account is signed in. Only the account id is kept, in the
/// platform keystore (Android Keystore / iOS Keychain), never the phone number.
class SessionStore {
  const SessionStore();
  static const _key = 'session_account';
  static const _storage = FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String accountId) =>
      _storage.write(key: _key, value: accountId);
  Future<void> clear() => _storage.delete(key: _key);
}
