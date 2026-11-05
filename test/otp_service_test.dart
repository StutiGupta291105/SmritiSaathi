import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smriti_assist/services/api_client.dart';
import 'package:smriti_assist/services/otp_service.dart';

void main() {
  apiOtpTests();
  const phone = '+919876543210';

  test('correct code verifies', () async {
    final s = DevOtpService();
    expect(await s.verify(phone, DevOtpService.testCode), OtpResult.ok);
  });

  test('wrong codes are rejected, then the number is locked after 5', () async {
    final s = DevOtpService();
    for (var i = 0; i < 4; i++) {
      expect(await s.verify(phone, '000000'), OtpResult.wrong);
    }
    expect(await s.verify(phone, '000000'), OtpResult.locked);
    // Even the right code is refused while locked.
    expect(await s.verify(phone, DevOtpService.testCode), OtpResult.locked);
  });

  test('lock expires after the lock period', () async {
    var now = DateTime(2026, 1, 1, 10);
    final s = DevOtpService(now: () => now);
    for (var i = 0; i < 5; i++) {
      await s.verify(phone, '000000');
    }
    now = now.add(const Duration(minutes: DevOtpService.lockMinutes + 1));
    expect(await s.verify(phone, DevOtpService.testCode), OtpResult.ok);
  });

  test('failures are counted per phone number', () async {
    final s = DevOtpService();
    for (var i = 0; i < 5; i++) {
      await s.verify(phone, '000000');
    }
    expect(await s.verify('+919000000001', DevOtpService.testCode), OtpResult.ok);
  });
}

http.Response _j(int status, Object body) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

ApiOtpService _api(Future<http.Response> Function(http.Request) h) =>
    ApiOtpService(ApiClient(
        baseUrl: 'https://api.example.com',
        client: MockClient(h),
        tokens: MemoryTokenStore()));

void apiOtpTests() {
  group('ApiOtpService', () {
    test('send then verify signs in and exposes the server user', () async {
      final s = _api((r) async => r.url.path.endsWith('/request')
          ? _j(200, {'challenge_id': 'c1'})
          : _j(200, {
              'access_token': 'A',
              'refresh_token': 'R',
              'user': {'id': 'u1', 'role': 'patient', 'name': 'Asha'}
            }));
      expect(s.isTestMode, isFalse);
      expect(await s.send('+919876543210', role: 'patient', signUp: true), OtpResult.ok);
      expect(await s.verify('+919876543210', '123456', signUp: true, name: 'Asha'),
          OtpResult.ok);
      expect(s.serverUser!.id, 'u1');
    });

    test('verify without send fails', () async {
      final s = _api((r) async => _j(200, {}));
      expect(await s.verify('+919876543210', '123456'), OtpResult.failed);
    });

    test('server reasons map to results', () async {
      Future<OtpResult> run(int status, String detail) async {
        final s = _api((r) async => r.url.path.endsWith('/request')
            ? _j(200, {'challenge_id': 'c'})
            : _j(status, {'detail': detail}));
        await s.send('+919876543210');
        return s.verify('+919876543210', '000000');
      }

      expect(await run(400, 'otp_invalid'), OtpResult.wrong);
      expect(await run(429, 'otp_locked'), OtpResult.locked);
      expect(await run(404, 'no_account'), OtpResult.noAccount);
      expect(await run(409, 'account_exists'), OtpResult.accountExists);
      expect(await run(500, 'boom'), OtpResult.failed);
    });

    test('no connection is reported as offline', () async {
      final s = _api((r) async => throw http.ClientException('x'));
      expect(await s.send('+919876543210'), OtpResult.offline);
    });
  });
}
