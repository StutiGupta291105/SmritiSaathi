import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/features/remote/remote_home.dart';
import 'package:smriti_assist/services/api_client.dart';

http.Response _j(int s, Object b) =>
    http.Response(jsonEncode(b), s, headers: {'content-type': 'application/json'});

Widget _app(ApiClient api, {VoidCallback? signedOut}) => MaterialApp(
    home: RemoteHome(
        key: UniqueKey(),
        api: api,
        user: const ServerUser('u', 'caretaker', 'Ravi'),
        lang: 'en',
        onLogout: () {},
        onSignedOut: signedOut));

ApiClient _api(Future<http.Response> Function(http.Request) h) => ApiClient(
    baseUrl: 'https://api.example.com',
    tokens: MemoryTokenStore(),
    client: MockClient(h));

const _report = {
  'patient': {'id': 'p1', 'display_name': 'Asha', 'baseline_level': 2},
  'range_days': 7,
  'games_played': 4,
  'streak': 2,
  'last_played': '2026-03-10T10:00:00',
  'daily': [0, 1, 0, 2, 1, 0, 0],
  'per_game': [
    {'game': 'memory_match', 'sessions': 4, 'accuracy': 0.75}
  ],
  'adherence': {'expected': 6, 'done': 3},
  'alerts': [
    {'kind': 'inactive', 'severity': 'attention', 'a': 3, 'b': 0}
  ],
};

void main() {
  testWidgets('shows invitations and patients, and accepts an invite', (t) async {
    var accepted = false;
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites/i1/accept') {
        accepted = true;
        return _j(200, {'status': 'accepted'});
      }
      if (p == '/v1/invites') {
        return _j(200, accepted
            ? []
            : [
                {
                  'id': 'i1',
                  'patient_display_name': 'Meera',
                  'member_role': 'caretaker',
                  'created_at': '2026-03-01T00:00:00'
                }
              ]);
      }
      if (p == '/v1/my-patients') {
        return _j(200, [
          {
            'patient_id': 'p1',
            'display_name': 'Asha',
            'link_role': 'caretaker',
            'alerts_needing_attention': 1
          }
        ]);
      }
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(accepted, isTrue);
    expect(find.text('Meera'), findsNothing);
  });

  testWidgets('opening a patient shows the shared report and alerts', (t) async {
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') {
        return _j(200, [
          {
            'patient_id': 'p1',
            'display_name': 'Asha',
            'link_role': 'caretaker',
            'alerts_needing_attention': 0
          }
        ]);
      }
      if (p == '/v1/patients/p1/report') return _j(200, _report);
      return _j(404, {'detail': 'x'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha'));
    await t.pumpAndSettle();
    expect(find.text('Has not played for 3 days.'), findsOneWidget);
    expect(find.textContaining('Games played: 4'), findsOneWidget);
    expect(find.textContaining('75%'), findsOneWidget);
  });

  testWidgets('a revoked share is explained, an expired login signs out', (t) async {
    final api = _api((r) async {
      final p = r.url.path;
      if (p == '/v1/invites') return _j(200, []);
      if (p == '/v1/my-patients') {
        return _j(200, [
          {'patient_id': 'p1', 'display_name': 'Asha', 'alerts_needing_attention': 0}
        ]);
      }
      return _j(404, {'detail': 'not_found'});
    });
    await t.pumpWidget(_app(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha'));
    await t.pumpAndSettle();
    expect(find.text('This person is no longer sharing with you.'), findsOneWidget);

    var out = false;
    final expired = _api((r) async => _j(401, {'detail': 'invalid_token'}));
    await t.pumpWidget(_app(expired, signedOut: () => out = true));
    await t.pumpAndSettle();
    expect(out, isTrue);
  });
}
