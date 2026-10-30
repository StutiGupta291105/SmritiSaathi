import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// A failed call. [status] is 0 when the server could not be reached at all.
class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final String detail;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status, $detail)';
}

/// The signed-in server account.
class ServerUser {
  const ServerUser(this.id, this.role, this.name, [this.careId, this.contactPhone]);
  final String id, role, name;

  /// The number a caretaker or doctor lets their patients call; null when none.
  final String? contactPhone;

  /// What a patient types to invite a caretaker or doctor; null for patients
  /// and for sessions saved before IDs existed.
  final String? careId;

  Map<String, Object?> toJson() =>
      {'id': id, 'role': role, 'name': name, 'care_id': careId, 'contact_phone': contactPhone};
  factory ServerUser.fromJson(Map<String, dynamic> j) => ServerUser(
      j['id'] as String, j['role'] as String, j['name'] as String,
      j['care_id'] as String?, j['contact_phone'] as String?);
}

/// Where the tokens and the signed-in user are kept. The platform keystore in
/// the app; in memory in tests.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// HTTP client for the Smriti Sathi API.
///
///  * HTTPS only, except plain http to a machine on this computer or the
///    Android emulator host (for development).
///  * An expired access token is refreshed once and the call retried. If the
///    refresh fails, the stored tokens are cleared and the caller sees 401.
///  * Network failures and timeouts become `ApiException(0, ...)`.
class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? client,
    TokenStore? tokens,
    // A free test server sleeps when idle and takes up to a minute to wake.
    this.timeout = const Duration(seconds: 45),
  })  : baseUri = _validated(baseUrl),
        _http = client ?? http.Client(),
        _tokens = tokens ?? const SecureTokenStore();

  final Uri baseUri;
  final http.Client _http;
  final TokenStore _tokens;
  final Duration timeout;

  static const _kAccess = 'api_access';
  static const _kRefresh = 'api_refresh';
  static const _kUser = 'api_user';

  static const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  static Uri _validated(String url) {
    final u = Uri.parse(url.endsWith('/') ? url.substring(0, url.length - 1) : url);
    final secure = u.scheme == 'https';
    final local = u.scheme == 'http' && _localHosts.contains(u.host);
    if (!secure && !local) {
      throw ArgumentError('The API address must use https (got "$url")');
    }
    return u;
  }

  // ---- session state -------------------------------------------------------

  Future<bool> get hasSession async => (await _tokens.read(_kRefresh)) != null;

  Future<ServerUser?> currentUser() async {
    final raw = await _tokens.read(_kUser);
    if (raw == null || await _tokens.read(_kRefresh) == null) return null;
    return ServerUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _saveSession(Map<String, dynamic> j) async {
    await _tokens.write(_kAccess, j['access_token'] as String);
    await _tokens.write(_kRefresh, j['refresh_token'] as String);
    final u = j['user'];
    if (u != null) await _tokens.write(_kUser, jsonEncode(u));
  }

  Future<void> clearSession() async {
    for (final k in [_kAccess, _kRefresh, _kUser]) {
      await _tokens.delete(k);
    }
  }

  // ---- transport -------------------------------------------------------------

  Future<Map<String, dynamic>> _raw(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    bool retried = false,
    Duration? wait,
  }) async {
    final target = Uri.parse(path); // may carry a query string
    final uri = baseUri.replace(
        path: '${baseUri.path}${target.path}',
        query: target.hasQuery ? target.query : null);
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (auth) {
      final token = await _tokens.read(_kAccess);
      if (token != null) headers['authorization'] = 'Bearer $token';
    }
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(
          await _http.send(req).timeout(wait ?? timeout));
    } on TimeoutException {
      throw ApiException(0, 'timeout');
    } on http.ClientException {
      throw ApiException(0, 'network');
    } on Exception {
      throw ApiException(0, 'network');
    }

    if (res.statusCode == 401 && auth && !retried && path != '/v1/auth/refresh') {
      if (await _refresh()) {
        return _raw(method, path, body: body, auth: auth, retried: true, wait: wait);
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return const {};
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    }
    var detail = 'error';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['detail'] is String) detail = j['detail'] as String;
    } catch (_) {}
    throw ApiException(res.statusCode, detail);
  }

  /// A binary download (a chat photo or voice note), signed in like any call.
  Future<Uint8List> _bytes(String path, {bool retried = false}) async {
    final uri = baseUri.replace(path: '${baseUri.path}$path');
    final token = await _tokens.read(_kAccess);
    http.Response res;
    try {
      final req = http.Request('GET', uri);
      if (token != null) req.headers['authorization'] = 'Bearer $token';
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'timeout');
    } on Exception {
      throw ApiException(0, 'network');
    }
    if (res.statusCode == 401 && !retried && await _refresh()) {
      return _bytes(path, retried: true);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw ApiException(res.statusCode, 'error');
  }

  Future<bool> _refresh() async {
    final refresh = await _tokens.read(_kRefresh);
    if (refresh == null) return false;
    try {
      final j = await _raw('POST', '/v1/auth/refresh',
          body: {'refresh_token': refresh}, auth: false, retried: true);
      await _saveSession(j);
      return true;
    } on ApiException catch (e) {
      if (!e.isNetwork) await clearSession(); // rejected: the session is over
      return false;
    }
  }

  // ---- auth --------------------------------------------------------------------

  Future<String> requestOtp(String phoneE164, String role) async {
    final j = await _raw('POST', '/v1/auth/otp/request',
        body: {'phone': phoneE164, 'role': role}, auth: false);
    return j['challenge_id'] as String;
  }

  Future<ServerUser> verifyOtp({
    required String challengeId,
    required String code,
    required String mode,
    String? name,
  }) async {
    final j = await _raw('POST', '/v1/auth/otp/verify',
        body: {
          'challenge_id': challengeId,
          'code': code,
          'mode': mode,
          if (name != null && name.isNotEmpty) 'name': name,
        },
        auth: false);
    await _saveSession(j);
    return ServerUser.fromJson(j['user'] as Map<String, dynamic>);
  }

  /// Ends the session on the server (best effort) and on this phone.
  Future<void> logout() async {
    final refresh = await _tokens.read(_kRefresh);
    if (refresh != null) {
      try {
        await _raw('POST', '/v1/auth/logout',
            body: {'refresh_token': refresh}, auth: false);
      } on ApiException {
        // Offline: the token still expires on its own.
      }
    }
    await clearSession();
  }

  // ---- patient -----------------------------------------------------------------

  Future<Map<String, dynamic>> createPatient({
    required String displayName,
    required String language,
    required int baselineLevel,
    required int tzOffsetMinutes,
  }) =>
      _raw('POST', '/v1/patients', body: {
        'display_name': displayName,
        'language': language,
        'baseline_level': baselineLevel,
        'tz_offset_minutes': tzOffsetMinutes,
      });

  Future<Map<String, dynamic>> myPatient() => _raw('GET', '/v1/patients/me');

  Future<Map<String, dynamic>> snapshot(String patientId) =>
      _raw('GET', '/v1/patients/$patientId/snapshot');

  Future<void> addConsents(String patientId, List<Map<String, Object?>> items) =>
      _raw('POST', '/v1/patients/$patientId/consents', body: {'consents': items});

  Future<Map<String, dynamic>> sync(String patientId, Map<String, Object?> body) =>
      _raw('POST', '/v1/patients/$patientId/sync', body: body);

  Future<Map<String, dynamic>> createInvite(
    String patientId, {
    required String role,
    String phoneE164 = '',
    String careId = '',
    required String name,
    String professionalId = '',
  }) =>
      _raw('POST', '/v1/patients/$patientId/invites', body: {
        'role': role,
        if (careId.isNotEmpty) 'care_id': careId else 'phone': phoneE164,
        'name': name,
        'professional_id': professionalId,
      });

  /// The signed-in account as the server sees it (includes the care ID).
  Future<ServerUser> me() async {
    final j = await _raw('GET', '/v1/auth/me');
    final u = ServerUser.fromJson(j);
    final raw = await _tokens.read(_kUser);
    if (raw != null) await _tokens.write(_kUser, jsonEncode(u.toJson()));
    return u;
  }

  Future<List<Map<String, dynamic>>> links(String patientId) async {
    final j = await _raw('GET', '/v1/patients/$patientId/links');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// One turn of 'Talk to Smriti' through the server. Needs the patient's own
  /// login and the 'companion' consent. 429 means today's limit was reached.
  Future<Map<String, dynamic>> companionChat(
    String patientId, {
    required List<Map<String, String>> messages,
    required String lang,
    required String firstName,
    required String nowText,
    required List<Map<String, Object?>> today,
  }) =>
      _raw('POST', '/v1/patients/$patientId/companion/chat', body: {
        'messages': messages,
        'lang': lang,
        'first_name': firstName,
        'now_text': nowText,
        'today': today,
      }, wait: const Duration(seconds: 70));

  /// Wakes a sleeping test server in the background so the first real request
  /// does not wait for it. Never throws.
  Future<void> wake() async {
    try {
      await _http
          .get(baseUri.replace(path: '${baseUri.path}/healthz'))
          .timeout(const Duration(seconds: 70));
    } catch (_) {}
  }

  Future<void> registerDevice(String token, String platform) =>
      _raw('POST', '/v1/devices', body: {'token': token, 'platform': platform});

  Future<void> unregisterDevice(String token, String platform) =>
      _raw('DELETE', '/v1/devices', body: {'token': token, 'platform': platform});

  Future<void> eraseServerData(String patientId) =>
      _raw('DELETE', '/v1/patients/$patientId');

  // ---- caretaker / doctor -------------------------------------------------------

  Future<List<Map<String, dynamic>>> myInvites() async {
    final j = await _raw('GET', '/v1/invites');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> acceptInvite(String id) => _raw('POST', '/v1/invites/$id/accept');
  Future<void> declineInvite(String id) => _raw('POST', '/v1/invites/$id/decline');

  Future<List<Map<String, dynamic>>> myPatients() async {
    final j = await _raw('GET', '/v1/my-patients');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> patientReminders(String patientId) async {
    final j = await _raw('GET', '/v1/patients/$patientId/reminders');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> report(String patientId, int days) =>
      _raw('GET', '/v1/patients/$patientId/report?days=$days');

  Future<void> setBaseline(String patientId, int level) =>
      _raw('PATCH', '/v1/patients/$patientId/baseline', body: {'baseline_level': level});

  Future<void> revokeLink(String linkId) => _raw('DELETE', '/v1/links/$linkId');

  // ---- chat -----------------------------------------------------------------

  /// Every conversation this account can open, with unread counts.
  Future<List<Map<String, dynamic>>> chatThreads() async {
    final j = await _raw('GET', '/v1/chat/threads');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The latest page, or only what is newer than [after], or an older page.
  Future<List<Map<String, dynamic>>> chatMessages(String linkId,
      {int after = 0, int before = 0}) async {
    final q = after > 0 ? '?after=$after' : before > 0 ? '?before=$before' : '';
    final j = await _raw('GET', '/v1/chat/$linkId/messages$q');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendChatMessage(
    String linkId, {
    required String kind, // text | image | voice
    String text = '',
    Uint8List? media,
    String mime = '',
    int durationMs = 0,
  }) =>
      _raw('POST', '/v1/chat/$linkId/messages', body: {
        'kind': kind,
        'text': text,
        if (media != null) 'media_b64': base64Encode(media),
        'mime': mime,
        'duration_ms': durationMs,
      });

  Future<Uint8List> chatMedia(int messageId) => _bytes('/v1/chat/media/$messageId');

  Future<void> chatMarkRead(String linkId, int upto) =>
      _raw('POST', '/v1/chat/$linkId/read', body: {'upto': upto});

  // ---- routines and reminders set by a caretaker or doctor -----------------

  Future<List<Map<String, dynamic>>> careReminders(String patientId) async {
    final j = await _raw('GET', '/v1/patients/$patientId/care-reminders');
    return ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> addCareReminder(
    String patientId, {
    required String kind,
    required String label,
    required int hour,
    required int minute,
    int daysMask = 127,
    String? onDate, // yyyy-mm-dd
  }) =>
      _raw('POST', '/v1/patients/$patientId/care-reminders', body: {
        'kind': kind,
        'label': label,
        'hour': hour,
        'minute': minute,
        'days_mask': daysMask,
        if (onDate != null) 'on_date': onDate,
      });

  Future<void> deleteCareReminder(String patientId, String reminderId) =>
      _raw('DELETE', '/v1/patients/$patientId/care-reminders/$reminderId');

  /// A caretaker or doctor chooses the number their patients may call ('' = none).
  Future<ServerUser> setContactPhone(String phoneE164) async {
    final j = await _raw('PUT', '/v1/auth/me/contact', body: {'phone': phoneE164});
    return ServerUser.fromJson(j);
  }

}
