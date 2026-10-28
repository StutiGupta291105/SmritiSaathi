import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/services/api_client.dart';

http.Response json(int status, Object body) => http.Response(
    jsonEncode(body), status, headers: {'content-type': 'application/json'});

const tokens = {
  'access_token': 'A1',
  'refresh_token': 'R1',
  'user': {'id': 'u1', 'role': 'patient', 'name': 'Asha'},
};

ApiClient make(MockClient c, [MemoryTokenStore? store]) => ApiClient(
    baseUrl: 'https://api.example.com', client: c, tokens: store ?? MemoryTokenStore());

void main() {
  group('address rules', () {
    test('plain http to a real host is refused', () {
      expect(() => ApiClient(baseUrl: 'http://api.example.com'), throwsArgumentError);
      expect(() => ApiClient(baseUrl: 'ftp://x'), throwsArgumentError);
    });

    test('https and local development addresses are accepted', () {
      ApiClient(baseUrl: 'https://api.example.com/');
      ApiClient(baseUrl: 'http://localhost:8000');
      ApiClient(baseUrl: 'http://10.0.2.2:8000');
    });
  });

  group('sign-in', () {
    test('verify saves the session and the user', () async {
      final store = MemoryTokenStore();
      final api = make(MockClient((r) async {
        expect(r.url.path, '/v1/auth/otp/verify');
        expect(jsonDecode(r.body)['mode'], 'signup');
        return json(200, tokens);
      }), store);
      final u = await api.verifyOtp(
          challengeId: 'c', code: '123456', mode: 'signup', name: 'Asha');
      expect(u.role, 'patient');
      expect(await api.hasSession, isTrue);
      expect((await api.currentUser())!.name, 'Asha');
      expect(store.data['api_refresh'], 'R1');
    });

    test('server errors carry their reason', () async {
      final api = make(MockClient((r) async => json(404, {'detail': 'no_account'})));
      try {
        await api.verifyOtp(challengeId: 'c', code: '123456', mode: 'login');
        fail('should throw');
      } on ApiException catch (e) {
        expect([e.status, e.detail], [404, 'no_account']);
      }
    });

    test('logout clears the session even when the server cannot be reached',
        () async {
      final store = MemoryTokenStore()
        ..data.addAll({'api_access': 'A', 'api_refresh': 'R', 'api_user': '{}'});
      final api = make(MockClient((r) async => throw http.ClientException('offline')), store);
      await api.logout();
      expect(store.data, isEmpty);
      expect(await api.hasSession, isFalse);
    });
  });

  group('tokens', () {
    test('requests carry the access token', () async {
      final store = MemoryTokenStore()..data['api_access'] = 'TOK';
      String? seen;
      final api = make(MockClient((r) async {
        seen = r.headers['authorization'];
        return json(200, []);
      }), store);
      await api.myPatients();
      expect(seen, 'Bearer TOK');
    });

    test('an expired token is refreshed once and the call retried', () async {
      final store = MemoryTokenStore()
        ..data.addAll({'api_access': 'OLD', 'api_refresh': 'R0'});
      var calls = <String>[];
      final api = make(MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        if (r.url.path == '/v1/auth/refresh') {
          expect(jsonDecode(r.body)['refresh_token'], 'R0');
          return json(200, tokens);
        }
        return r.headers['authorization'] == 'Bearer A1'
            ? json(200, [{'patient_id': 'p'}])
            : json(401, {'detail': 'invalid_token'});
      }), store);
      final out = await api.myPatients();
      expect(out.single['patient_id'], 'p');
      expect(calls, ['GET /v1/my-patients', 'POST /v1/auth/refresh', 'GET /v1/my-patients']);
      expect(store.data['api_refresh'], 'R1'); // rotated
    });

    test('a rejected refresh ends the session and reports 401', () async {
      final store = MemoryTokenStore()
        ..data.addAll({'api_access': 'OLD', 'api_refresh': 'R0', 'api_user': '{}'});
      final api = make(MockClient((r) async => json(401, {'detail': 'invalid_token'})), store);
      await expectLater(api.myPatients(),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(store.data, isEmpty);
    });

    test('being offline during a refresh keeps the session', () async {
      final store = MemoryTokenStore()
        ..data.addAll({'api_access': 'OLD', 'api_refresh': 'R0'});
      final api = make(MockClient((r) async {
        if (r.url.path == '/v1/auth/refresh') throw http.ClientException('offline');
        return json(401, {'detail': 'invalid_token'});
      }), store);
      await expectLater(api.myPatients(), throwsA(isA<ApiException>()));
      expect(store.data['api_refresh'], 'R0');
    });

    test('there is never more than one retry', () async {
      final store = MemoryTokenStore()
        ..data.addAll({'api_access': 'OLD', 'api_refresh': 'R0'});
      var n = 0;
      final api = make(MockClient((r) async {
        n++;
        if (r.url.path == '/v1/auth/refresh') return json(200, tokens);
        return json(401, {'detail': 'invalid_token'});
      }), store);
      await expectLater(api.myPatients(), throwsA(isA<ApiException>()));
      expect(n, 3); // call, refresh, one retry
    });
  });

  group('failures', () {
    test('no connection becomes a network error', () async {
      final api = make(MockClient((r) async => throw http.ClientException('x')));
      try {
        await api.requestOtp('+919876543210', 'patient');
        fail('should throw');
      } on ApiException catch (e) {
        expect(e.isNetwork, isTrue);
      }
    });

    test('a slow server becomes a network error', () async {
      final api = ApiClient(
        baseUrl: 'https://api.example.com',
        tokens: MemoryTokenStore(),
        timeout: const Duration(milliseconds: 50),
        client: MockClient((r) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return json(200, {});
        }),
      );
      await expectLater(api.requestOtp('+919876543210', 'patient'),
          throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
    });

    test('lists are parsed and 204 answers are fine', () async {
      final api = make(MockClient((r) async => r.method == 'DELETE'
          ? http.Response('', 204)
          : json(200, [{'id': 'l1', 'status': 'pending'}])));
      expect((await api.links('p1')).single['status'], 'pending');
      await api.revokeLink('l1');
    });
  });
}
