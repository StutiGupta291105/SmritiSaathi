enum OtpResult { ok, wrong, locked }

/// Phone-number verification. The real implementation (SMS provider plus
/// server-side code check, rate limiting and expiry) comes with the backend;
/// the screens only know this interface.
abstract class OtpService {
  /// True while codes are NOT really sent. The UI shows a visible banner.
  bool get isTestMode;
  Future<void> send(String phoneE164);
  Future<OtpResult> verify(String phoneE164, String code);
}

/// TEST MODE ONLY. Accepts the fixed code [testCode] and sends no SMS, so it
/// provides no real security: anyone who knows the code can sign in as anyone
/// on this device. It must be replaced before any real deployment.
class DevOtpService implements OtpService {
  DevOtpService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const testCode = '123456';
  static const maxAttempts = 5;
  static const lockMinutes = 15;

  final DateTime Function() _now;
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  @override
  bool get isTestMode => true;

  @override
  Future<void> send(String phoneE164) async {}

  @override
  Future<OtpResult> verify(String phoneE164, String code) async {
    final until = _lockedUntil[phoneE164];
    if (until != null) {
      if (_now().isBefore(until)) return OtpResult.locked;
      _lockedUntil.remove(phoneE164);
      _failures.remove(phoneE164);
    }
    if (code.trim() == testCode) {
      _failures.remove(phoneE164);
      return OtpResult.ok;
    }
    final n = (_failures[phoneE164] ?? 0) + 1;
    _failures[phoneE164] = n;
    if (n >= maxAttempts) {
      _lockedUntil[phoneE164] = _now().add(const Duration(minutes: lockMinutes));
      return OtpResult.locked;
    }
    return OtpResult.wrong;
  }
}
