import '../core/config.dart';
import 'api_client.dart';

enum OtpResult { ok, wrong, locked, offline, noAccount, accountExists, failed }

/// Phone-number verification. [ApiOtpService] talks to the server (real SMS,
/// code check, rate limiting and expiry happen there); [DevOtpService] is the
/// offline test stand-in. The screens only know this interface.
abstract class OtpService {
  /// True while codes are NOT really sent. The UI shows a visible banner.
  bool get isTestMode;

  /// The server account behind the last successful [verify]; null offline.
  ServerUser? get serverUser;

  /// Sends the code. Anything other than [OtpResult.ok] is a failure.
  Future<OtpResult> send(String phoneE164,
      {String role = 'patient', bool signUp = false});

  Future<OtpResult> verify(String phoneE164, String code,
      {String role = 'patient', bool signUp = false, String? name});
}

/// Real verification through the Smriti Sathi API.
class ApiOtpService implements OtpService {
  ApiOtpService(this.api);
  final ApiClient api;
  String? _challengeId;
  ServerUser? _user;

  @override
  bool get isTestMode => false;

  @override
  ServerUser? get serverUser => _user;

  OtpResult _map(ApiException e) {
    if (e.isNetwork) return OtpResult.offline;
    switch (e.detail) {
      case 'otp_invalid':
        return OtpResult.wrong;
      case 'otp_locked':
      case 'rate_limited':
        return OtpResult.locked;
      case 'no_account':
        return OtpResult.noAccount;
      case 'account_exists':
        return OtpResult.accountExists;
    }
    return e.status == 429 ? OtpResult.locked : OtpResult.failed;
  }

  @override
  Future<OtpResult> send(String phoneE164,
      {String role = 'patient', bool signUp = false}) async {
    try {
      _challengeId = await api.requestOtp(phoneE164, role);
      return OtpResult.ok;
    } on ApiException catch (e) {
      return _map(e);
    }
  }

  @override
  Future<OtpResult> verify(String phoneE164, String code,
      {String role = 'patient', bool signUp = false, String? name}) async {
    final id = _challengeId;
    if (id == null) return OtpResult.failed;
    try {
      _user = await api.verifyOtp(
          challengeId: id,
          code: code.trim(),
          mode: signUp ? 'signup' : 'login',
          name: name);
      _challengeId = null;
      return OtpResult.ok;
    } on ApiException catch (e) {
      return _map(e);
    }
  }
}

/// The service for this build: the server when an API address was compiled in,
/// otherwise the offline test stand-in.
OtpService defaultOtpService(ApiClient? api) =>
    kOnlineConfigured && api != null ? ApiOtpService(api) : DevOtpService();

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
  ServerUser? get serverUser => null;

  @override
  Future<OtpResult> send(String phoneE164,
          {String role = 'patient', bool signUp = false}) async =>
      OtpResult.ok;

  @override
  Future<OtpResult> verify(String phoneE164, String code,
      {String role = 'patient', bool signUp = false, String? name}) async {
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
