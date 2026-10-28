import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/services/otp_service.dart';

void main() {
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
