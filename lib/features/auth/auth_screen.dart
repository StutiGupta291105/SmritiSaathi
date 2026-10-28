import 'package:flutter/material.dart';

import '../../core/profile.dart';
import '../../core/strings.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';
import '../../data/session_store.dart';
import '../../services/otp_service.dart';

/// Login and account creation: role, mobile number, OTP. Account existence is
/// only revealed after the OTP is verified, so the screen cannot be used to
/// find out whether a number is registered.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.db,
    required this.otp,
    required this.session,
    required this.lang,
    required this.onLangChanged,
    required this.onLoggedIn,
    this.initialSignUp = false,
    this.onBack,
  });
  final AppDatabase db;
  final OtpService otp;
  final SessionStore session;
  final String lang;
  final ValueChanged<String> onLangChanged;
  final VoidCallback onLoggedIn;
  final bool initialSignUp;
  final VoidCallback? onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.initialSignUp;
  String _role = 'patient';
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _e164; // set once the OTP has been sent
  String? _errorKey;
  bool _busy = false;

  String t(String k) => tr(widget.lang, k);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _fail(String key) => setState(() {
        _errorKey = key;
        _busy = false;
      });

  Future<void> _sendOtp() async {
    final e164 = normalizePhone(_phone.text);
    if (e164 == null) return _fail('errPhone');
    if (_signUp && _name.text.trim().isEmpty) return _fail('errName');
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    final sent = await widget.otp.send(e164, role: _role, signUp: _signUp);
    if (sent != OtpResult.ok) return _fail(_otpErrorKey(sent));
    setState(() {
      _e164 = e164;
      _busy = false;
    });
  }

  Future<void> _verify() async {
    final e164 = _e164!;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    final result = await widget.otp.verify(e164, _code.text,
        role: _role, signUp: _signUp, name: _name.text.trim());
    if (result != OtpResult.ok) return _fail(_otpErrorKey(result));
    final serverUser = widget.otp.serverUser;

    // The server decides who this is; the phone keeps its own encrypted copy.
    var account = serverUser == null
        ? null
        : await widget.db.accountByServerId(serverUser.id);
    account ??= await widget.db.accountByPhoneRole(e164, _role);
    String accountId;
    if (account != null) {
      accountId = account['id'] as String;
    } else if (_signUp || serverUser != null) {
      try {
        accountId = await widget.db.createAccount(
            phone: e164,
            role: _role,
            name: serverUser?.name ?? _name.text.trim());
      } on StateError {
        return _fail('errAccountExists');
      }
    } else {
      return _fail('errNoAccount');
    }
    if (serverUser != null) {
      await widget.db.linkServerAccount(accountId, serverUser.id);
    }
    await widget.session.write(accountId);
    await widget.db.recordLogin(accountId);
    widget.onLoggedIn();
  }

  String _otpErrorKey(OtpResult r) {
    switch (r) {
      case OtpResult.wrong:
        return 'errOtpWrong';
      case OtpResult.locked:
        return 'errOtpLocked';
      case OtpResult.offline:
        return 'errOffline';
      case OtpResult.noAccount:
        return 'errNoAccount';
      case OtpResult.accountExists:
        return 'errAccountExists';
      default:
        return 'errOtpFailed';
    }
  }

  void _switchMode() => setState(() {
        _signUp = !_signUp;
        _e164 = null;
        _errorKey = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingForOtp = _e164 != null;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack),
        actions: [
          TextButton(
            onPressed: () =>
                widget.onLangChanged(widget.lang == 'en' ? 'hi' : 'en'),
            child: Text(widget.lang == 'en' ? 'हिन्दी' : 'English',
                style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            BrandLogo(subtitle: t('brandSub')),
            const SizedBox(height: 16),
            if (widget.otp.isTestMode)
              Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(t('otpTestMode'),
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
            const SizedBox(height: 8),
            Text(_signUp ? t('createAccount') : t('login'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(t('iAm'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: waitingForOtp,
              child: Opacity(
                opacity: waitingForOtp ? 0.5 : 1,
                child: PillTabs(
                  labels: [
                    for (final r in kRoles)
                      t('role${r[0].toUpperCase()}${r.substring(1)}')
                  ],
                  selected: kRoles.indexOf(_role),
                  onSelected: (i) => setState(() => _role = kRoles[i]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_signUp)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _name,
                  enabled: !waitingForOtp,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                      labelText: t('yourName'),
                      ),
                ),
              ),
            TextField(
              controller: _phone,
              enabled: !waitingForOtp,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                  labelText: t('phoneNumber'),
                  prefixText: '+91 ',
                  ),
            ),
            const SizedBox(height: 12),
            if (waitingForOtp) ...[
              Text('${t('otpSentTo')} ${maskPhone(_e164!)}',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(fontSize: 24, letterSpacing: 6),
                decoration: InputDecoration(
                    labelText: t('enterOtp'), ),
              ),
            ],
            if (_errorKey != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t(_errorKey!),
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : (waitingForOtp ? _verify : _sendOtp),
              child: Text(waitingForOtp ? t('verifyOtp') : t('sendOtp')),
            ),
            if (waitingForOtp)
              TextButton(
                onPressed: () => setState(() {
                  _e164 = null;
                  _code.clear();
                  _errorKey = null;
                }),
                child: Text(t('changeNumber'),
                    style: const TextStyle(fontSize: 18)),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _switchMode,
              child: Text(_signUp ? t('haveAccount') : t('noAccountYet'),
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
