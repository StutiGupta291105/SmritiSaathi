import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_admin/api.dart';
import 'package:smriti_admin/main.dart';

http.Response _j(int s, Object b) => http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

final _link = {
  'id': 'l1', 'status': 'accepted', 'member_role': 'doctor', 'patient_id': 'p1', 'patient_user_id': 'up1',
  'patient_name': 'Asha Devi', 'member_user_id': 'ud1', 'member_name': 'Dr Rao', 'member_care_id': 'DR-ABC234',
  'member_verified': true, 'invited_name': 'Dr Rao', 'professional_id': null, 'created_at': '2026-10-01T10:00:00',
  'updated_at': '2026-10-02T10:00:00', 'message_count': 4, 'last_message_at': null,
};

final _audit = [
  {'id': 9, 'ts': '2026-10-30T09:00:00', 'actor': 'u2', 'actor_name': 'Snoop (caretaker)', 'action': 'access_denied', 'detail': 'patient=p1 role=caretaker', 'hash': 'abcdef0123456789'},
  {'id': 8, 'ts': '2026-10-30T08:00:00', 'actor': 'ud1', 'actor_name': 'Dr Rao (doctor)', 'action': 'login', 'detail': 'role=doctor', 'hash': '0123456789abcdef'},
];

final calls = <String>[];

Future<http.Response> _server(http.Request r) async {
  calls.add('${r.method} ${r.url.path}');
  final p = r.url.path;
  if (p == '/v1/admin/login') {
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    if (b['password'] != 'right password!') return _j(401, {'detail': 'invalid_credentials'});
    return _j(200, {'access_token': 'tok', 'username': 'root', 'expires_in': 1800});
  }
  if (r.headers['authorization'] != 'Bearer tok') return _j(401, {'detail': 'invalid_token'});
  if (p == '/v1/admin/overview') {
    return _j(200, {
      'users': {'patient': 12, 'doctor': 3, 'caretaker': 7}, 'doctors_unverified': 2,
      'links': {'pending': 1, 'accepted': 9, 'declined': 0, 'revoked': 1}, 'patients_without_supervisor': 4,
      'sessions_24h': 30, 'messages_24h': 11, 'care_reminders': 5, 'devices': 8, 'logins_24h': 14,
      'otp_failed_24h': 3, 'access_denied_24h': 1, 'refresh_reuse_24h': 0, 'admin_logins_24h': 1, 'audit_entries': 412,
    });
  }
  if (p == '/v1/admin/patients') {
    return _j(200, {'total': 1, 'items': [
      {'patient_id': 'p1', 'user_id': 'up1', 'name': 'Asha Devi', 'phone_last4': '3210', 'language': 'hi', 'baseline_level': 3,
       'created_at': '2026-09-01T00:00:00', 'caregivers': [{'role': 'caretaker', 'name': 'Ravi', 'user_id': 'uc1'}],
       'doctors': [{'role': 'doctor', 'name': 'Dr Rao', 'user_id': 'ud1'}],
       'sharing': {'caregiver': true, 'doctor': true, 'sync': true, 'companion': false}, 'sessions': 22, 'last_played': '2026-10-29T10:00:00'},
    ]});
  }
  if (p == '/v1/admin/users/up1') {
    return _j(200, {
      'user': {'id': 'up1', 'role': 'patient', 'name': 'Asha Devi', 'phone_last4': '3210', 'care_id': null, 'verified': false, 'created_at': '2026-09-01T00:00:00', 'last_login_at': '2026-10-29T09:00:00'},
      'devices': 1, 'contact_phone_shared': false,
      'patient': {'patient_id': 'p1', 'name': 'Asha Devi', 'language': 'hi', 'baseline_level': 3, 'tz_offset_minutes': 330, 'created_at': '2026-09-01T00:00:00',
        'sessions': 22, 'last_played': '2026-10-29T10:00:00', 'care_reminders': 2, 'consent_changes': 6,
        'consents': {'gameplay': {'granted': true, 'at': '2026-09-01T00:00:00', 'by': 'Asha (self)'}, 'doctor_share': {'granted': true, 'at': '2026-09-02T00:00:00', 'by': 'Asha (self)'}, 'location': {'granted': false, 'at': null, 'by': null}}},
      'supervisors': [_link], 'recent_activity': _audit,
    });
  }
  if (p == '/v1/admin/users') {
    final role = r.url.queryParameters['role'];
    return _j(200, {'total': 1, 'items': [
      {'id': 'ud1', 'role': role, 'name': 'Dr Rao', 'phone_last4': '2222', 'care_id': 'DR-ABC234', 'verified': false, 'created_at': '2026-09-02T00:00:00', 'last_login_at': '2026-10-29T09:00:00', 'patients': 1},
    ]});
  }
  if (p == '/v1/admin/links') {
    return _j(200, {'total': 1, 'items': [_link]});
  }
  if (p == '/v1/admin/audit/verify') return _j(200, {'ok': true, 'head': '8:abc', 'entries': 412});
  if (p == '/v1/admin/audit') {
    return _j(200, {'total': 2, 'items': _audit, 'actions': ['access_denied', 'login']});
  }
  if (p == '/v1/admin/security') {
    return _j(200, {
      'last_24h': {'otp_failed': 3, 'access_denied': 1, 'refresh_reuse_detected': 0, 'admin_login_failed': 0, 'login': 14, 'report_viewed': 5},
      'last_7d': {'access_denied': 2, 'consent_recorded': 4, 'patient_erased': 0, 'patient_exported': 1, 'links_revoked': 0, 'link_revoked': 1},
      'doctors_unverified': [{'id': 'ud1', 'name': 'Dr Rao', 'care_id': 'DR-ABC234', 'created_at': '2026-09-02T00:00:00'}],
      'top_report_viewers_7d': [{'actor': 'ud1', 'name': 'Dr Rao (doctor)', 'views': 9}],
      'locked_admins': [], 'recent_events': _audit,
    });
  }
  return _j(404, {'detail': 'not_found'});
}

Widget _app() => AdminApp(apiFactory: (url) => AdminApi(url, client: MockClient(_server)));

Future<void> _signIn(WidgetTester t, {String password = 'right password!'}) async {
  await t.binding.setSurfaceSize(const Size(1400, 900));
  await t.pumpWidget(_app());
  await t.enterText(find.byKey(const ValueKey('username')), 'root');
  await t.enterText(find.byKey(const ValueKey('password')), password);
  await t.enterText(find.byKey(const ValueKey('code')), '123456');
  await t.tap(find.byKey(const ValueKey('signIn')));
  await t.pumpAndSettle();
}

/// Tests draw with a square placeholder font by default, which makes every text far
/// wider than real text. Load Roboto from the Flutter SDK so layouts are realistic.
Future<void> _loadRoboto() async {
  var root = Platform.environment['FLUTTER_ROOT'] ?? '';
  if (root.isEmpty) {
    // .../flutter/bin/cache/dart-sdk/bin/dart  ->  .../flutter
    root = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    final file = File('${dir.path}/Roboto-$f.ttf');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);
  setUp(calls.clear);

  testWidgets('wrong details are refused, right ones open the portal', (t) async {
    await _signIn(t, password: 'nope');
    expect(find.byKey(const ValueKey('loginError')), findsOneWidget);
    expect(find.text('Wrong username, password or code.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('password')), 'right password!');
    await t.tap(find.byKey(const ValueKey('signIn')));
    await t.pumpAndSettle();
    expect(find.text('READ ONLY'), findsOneWidget);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('12'), findsOneWidget); // patients
    expect(find.text('4'), findsWidgets); // patients with no supervisor
  });

  testWidgets('every page loads its data; the patient page shows who supervises them', (t) async {
    await _signIn(t);
    await t.tap(find.byKey(const ValueKey('nav1')));
    await t.pumpAndSettle();
    expect(find.text('Asha Devi'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget); // caregiver
    expect(find.text('Dr Rao'), findsOneWidget); // doctor
    expect(find.text('••••3210'), findsOneWidget);
    await t.tap(find.text('Asha Devi'));
    await t.pumpAndSettle();
    final list = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.textContaining('doctor_share: allowed'), 300, scrollable: list);
    expect(find.textContaining('doctor_share: allowed'), findsOneWidget);
    expect(find.textContaining('location: off'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Supervised by'), 300, scrollable: list);
    expect(find.text('Supervised by'), findsOneWidget);
    await t.scrollUntilVisible(find.text('DR-ABC234'), 300, scrollable: list);
    expect(find.text('DR-ABC234'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('nav2')));
    await t.pumpAndSettle();
    expect(find.text('not verified'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nav3')));
    await t.pumpAndSettle();
    expect(find.text('Caregivers'), findsWidgets);

    await t.tap(find.byKey(const ValueKey('nav4')));
    await t.pumpAndSettle();
    expect(find.textContaining('Doctors and their patients'), findsOneWidget);
    expect(find.byKey(const ValueKey('patient_l1')), findsOneWidget);
    await t.tap(find.text('All links'));
    await t.pumpAndSettle();
    expect(find.text('accepted'), findsWidgets);

    await t.tap(find.byKey(const ValueKey('nav5')));
    await t.pumpAndSettle();
    expect(find.text('Snoop (caretaker)'), findsOneWidget);
    expect(find.text('access_denied'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('verifyLog')));
    await t.pumpAndSettle();
    expect(find.textContaining('Log intact: 412 entries'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('nav6')));
    await t.pumpAndSettle();
    expect(find.text('Dr Rao (doctor)'), findsWidgets);
    expect(find.textContaining('9 views'), findsOneWidget);
  });

  testWidgets('after signing in, the portal only ever sends GET requests', (t) async {
    await _signIn(t);
    for (var i = 1; i <= 6; i++) {
      await t.tap(find.byKey(ValueKey('nav$i')));
      await t.pumpAndSettle();
    }
    expect(calls.where((c) => c != 'POST /v1/admin/login').every((c) => c.startsWith('GET ')), isTrue, reason: '$calls');
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('an expired session returns to sign-in with a message', (t) async {
    await _signIn(t);
    // a server that forgets the token
    final api = AdminApi('https://x.example', client: MockClient((r) async => _j(401, {'detail': 'invalid_token'})));
    expect(() async => await api.overview(), throwsA(isA<AdminApiException>().having((e) => e.isUnauthorized, 'unauthorized', isTrue)));
  });

  test('the client has no way to write: one POST (sign-in) and nothing else', () {
    final src = File('lib/api.dart').readAsStringSync();
    expect(RegExp(r'\.post\(').allMatches(src).length, 1);
    for (final bad in ['.put(', '.patch(', '.delete(', '.send(', 'MultipartRequest']) {
      expect(src.contains(bad), isFalse, reason: bad);
    }
    for (final f in Directory('lib/screens').listSync().whereType<File>()) {
      final s = f.readAsStringSync();
      expect(s.contains('api.login'), f.path.endsWith('login.dart'), reason: f.path);
    }
  });
}
