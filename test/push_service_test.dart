import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/push_service.dart';

class _Source implements PushTokenSource {
  _Source(this.t);
  final String? t;
  @override
  Future<String?> token() async => t;
}

void main() {
  late List<String> calls;
  late MemoryTokenStore store;
  var fail = false;

  PushRegistrar make(String? token) {
    store = MemoryTokenStore();
    return PushRegistrar(
      ApiClient(
          baseUrl: 'https://api.example.com',
          tokens: MemoryTokenStore()..data.addAll({'api_access': 'A', 'api_refresh': 'R'}),
          client: MockClient((r) async {
            calls.add('${r.method} ${r.url.path} ${jsonDecode(r.body)['platform']}');
            return fail
                ? http.Response('{"detail":"x"}', 500)
                : http.Response('', 204);
          })),
      _Source(token),
      store: store,
      platform: 'android',
    );
  }

  setUp(() {
    calls = [];
    fail = false;
  });

  test('the shipped build has no push source, so nothing is sent', () async {
    final reg = PushRegistrar(
        ApiClient(
            baseUrl: 'https://api.example.com',
            tokens: MemoryTokenStore(),
            client: MockClient((r) async {
              calls.add(r.url.path);
              return http.Response('', 204);
            })),
        const NoPush(),
        store: MemoryTokenStore());
    await reg.register();
    expect(calls, isEmpty);
  });

  test('registers a token, remembers it, and forgets it on sign-out', () async {
    final reg = make('t' * 40);
    await reg.register();
    expect(calls, ['POST /v1/devices android']);
    expect(store.data['push_token'], 't' * 40);
    await reg.unregister();
    expect(calls.last, 'DELETE /v1/devices android');
    expect(store.data, isEmpty);
    calls.clear();
    await reg.unregister(); // nothing remembered: no call
    expect(calls, isEmpty);
  });

  test('server trouble never breaks sign-in or sign-out', () async {
    final reg = make('t' * 40);
    fail = true;
    await reg.register();
    expect(store.data, isEmpty); // will retry next time
    store.data['push_token'] = 't' * 40;
    await reg.unregister();
    expect(store.data, isEmpty);
  });

  test('a missing or too-short token is ignored', () async {
    await make(null).register();
    await make('short').register();
    expect(calls, isEmpty);
  });
}
