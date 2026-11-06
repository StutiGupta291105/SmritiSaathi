import 'package:flutter/material.dart';

import '../../core/profile.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../data/session_store.dart';
import '../../services/otp_service.dart';
import 'garden_frame.dart';

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
  bool _offerOffline = false; // no connection: a new patient may start on the phone alone

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
    if (sent == OtpResult.offline && _signUp && _role == 'patient') {
      // Games and reminders need no server, so do not make a new patient wait for
      // a signal: offer to set up now and check the number later.
      setState(() {
        _offerOffline = true;
        _errorKey = 'errOffline';
        _busy = false;
      });
      return;
    }
    if (sent != OtpResult.ok) return _fail(_otpErrorKey(sent));
    setState(() {
      _e164 = e164;
      _busy = false;
    });
  }

  /// A new patient with no internet: the account lives on the phone only. The
  /// phone number is checked later (Settings > Connect online services), which
  /// is when sharing, chat and the AI helper start.
  Future<void> _startOffline() async {
    final e164 = normalizePhone(_phone.text);
    if (e164 == null) return _fail('errPhone');
    if (_name.text.trim().isEmpty) return _fail('errName');
    setState(() => _busy = true);
    try {
      final id = await widget.db
          .createAccount(phone: e164, role: 'patient', name: _name.text.trim());
      await widget.session.write(id);
      await widget.db.recordLogin(id);
      widget.onLoggedIn();
    } on StateError {
      _fail('errAccountExists');
    }
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

  IconData _roleIcon(String r) => switch (r) {
        'patient' => Icons.person_rounded,
        'caretaker' => Icons.volunteer_activism_rounded,
        _ => Icons.medical_services_rounded,
      };

  Widget _roleChips(bool locked) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in const ['patient', 'caretaker', 'doctor'])
          ChoiceChip(
            key: ValueKey('role_$r'),
            avatar: Icon(_roleIcon(r),
                size: 18, color: _role == r ? Colors.white : Palette.brandDeep),
            label: Text(t('role${r[0].toUpperCase()}${r.substring(1)}')),
            labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _role == r ? Colors.white : Palette.brandDeep),
            selected: _role == r,
            selectedColor: Palette.brand,
            backgroundColor: Colors.white,
            showCheckmark: false,
            side: BorderSide(color: _role == r ? Palette.brand : Palette.line),
            onSelected: locked ? null : (_) => setState(() => _role = r),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingForOtp = _e164 != null;
    // The steps are the same ones the person will go through; "About you" comes after
    // the code, on its own screen, for a new patient.
    final steps = [
      t('stepNumber'),
      t('stepCode'),
      if (_signUp && _role == 'patient') t('stepAbout'),
    ];
    return AuthFrame(
      lang: widget.lang,
      title: _signUp ? t('createAccount') : t('login'),
      subtitle: _signUp ? t('signUpSub') : t('loginSub'),
      steps: steps,
      heroHeight: 160,
      step: waitingForOtp ? 1 : 0,
      onBack: widget.onBack,
      onLangChanged: widget.onLangChanged,
      banner: widget.otp.isTestMode
          ? Card(
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(t('otpTestMode'), style: const TextStyle(fontSize: 15)),
              ),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('iAm'),
            style: const TextStyle(fontSize: 13.5, color: Palette.muted)),
        const SizedBox(height: 8),
        _roleChips(waitingForOtp),
        const SizedBox(height: 16),
        if (_signUp)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _name,
              enabled: !waitingForOtp,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                  labelText: t('yourName'),
                  prefixIcon: const Icon(Icons.badge_outlined)),
            ),
          ),
        TextField(
          controller: _phone,
          enabled: !waitingForOtp,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
              labelText: t('phoneNumber'),
              prefixText: '+91 ',
              prefixIcon: const Icon(Icons.phone_iphone_rounded)),
        ),
        const SizedBox(height: 12),
        if (waitingForOtp) ...[
          Text('${t('otpSentTo')} ${maskPhone(_e164!)}', style: kTitleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: t('enterOtp')),
          ),
        ],
        if (_errorKey != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t(_errorKey!),
                style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        if (_offerOffline) ...[
          Text(t('offlineStartNote'),
              key: const ValueKey('offlineNote'),
              style: const TextStyle(fontSize: 14, color: Palette.muted, height: 1.35)),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const ValueKey('offlineStart'),
            onPressed: _busy ? null : _startOffline,
            child: Text(t('offlineStart')),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('authSubmit'),
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
            child: Text(t('changeNumber'), style: const TextStyle(fontSize: 16)),
          ),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('switchMode'),
          onPressed: _switchMode,
          child: Text(_signUp ? t('haveAccount') : t('noAccountYet'),
              style: const TextStyle(fontSize: 16)),
        ),
      ]),
    );
  }
}
