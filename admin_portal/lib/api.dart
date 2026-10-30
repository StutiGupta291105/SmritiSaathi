import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminApiException implements Exception {
  AdminApiException(this.status, this.code);
  final int status;
  final String code;
  bool get isUnauthorized => status == 401 && code != 'invalid_credentials';
  bool get isNetwork => status == 0;
  @override
  String toString() => 'AdminApiException($status, $code)';
}

/// Talks to the server's /v1/admin endpoints. Everything except [login] is a GET:
/// this class has no way to change anything on the server. The token lives in memory
/// only and expires after 30 minutes.
class AdminApi {
  AdminApi(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? _token;
  String username = '';

  bool get signedIn => _token != null;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = Uri.parse(baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl);
    return base.replace(
        path: '${base.path}$path',
        queryParameters: q == null || q.isEmpty ? null : q);
  }

  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(const Duration(seconds: 60));
    } catch (_) {
      throw AdminApiException(0, 'network');
    }
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 400) {
      throw AdminApiException(r.statusCode, '${body['detail'] ?? 'error'}');
    }
    return body;
  }

  Future<void> login(String user, String password, String code) async {
    final j = await _send(() => _client.post(_uri('/v1/admin/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(
            {'username': user, 'password': password, 'code': code})));
    _token = j['access_token'] as String;
    username = '${j['username']}';
  }

  void signOut() => _token = null;

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) =>
      _send(() => _client
          .get(_uri(path, q), headers: {'authorization': 'Bearer $_token'}));

  Future<Map<String, dynamic>> overview() => _get('/v1/admin/overview');
  Future<Map<String, dynamic>> users(
          {String role = '', String q = '', int offset = 0, int limit = 25}) =>
      _get('/v1/admin/users',
          {'role': role, 'q': q, 'offset': '$offset', 'limit': '$limit'});
  Future<Map<String, dynamic>> patients(
          {String q = '', int offset = 0, int limit = 25}) =>
      _get('/v1/admin/patients',
          {'q': q, 'offset': '$offset', 'limit': '$limit'});
  Future<Map<String, dynamic>> userDetail(String id) =>
      _get('/v1/admin/users/$id');
  Future<Map<String, dynamic>> links(
          {String status = '',
          String role = '',
          String q = '',
          int offset = 0,
          int limit = 25}) =>
      _get('/v1/admin/links', {
        'status': status,
        'role': role,
        'q': q,
        'offset': '$offset',
        'limit': '$limit'
      });
  Future<Map<String, dynamic>> audit(
          {String action = '',
          String q = '',
          int sinceHours = 0,
          int offset = 0,
          int limit = 50}) =>
      _get('/v1/admin/audit', {
        'action': action,
        'q': q,
        'since_hours': '$sinceHours',
        'offset': '$offset',
        'limit': '$limit'
      });
  Future<Map<String, dynamic>> verifyAudit() => _get('/v1/admin/audit/verify');
  Future<Map<String, dynamic>> security() => _get('/v1/admin/security');
}
