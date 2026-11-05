import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/otp_service.dart';

/// A patient who set up with no internet checks their phone number once here, so
/// that sharing with caregivers and doctors, chat and the AI helper can start.
/// Their games, reminders and progress are already on the phone and are kept.
class ConnectOnlineScreen extends StatefulWidget {
  const ConnectOnlineScreen({
    super.key,
    required this.otp,
    required this.db,
    required this.accountId,
    required this.phone,
    required this.name,
    required this.lang,
    required this.onConnected,
  });
  final OtpService otp;
  final AppDatabase db;
  final String accountId, phone, name, lang;
  final VoidCallback onConnected;

  @override
  State<ConnectOnlineScreen> createState() => _ConnectOnlineScreenState();
}

class _ConnectOnlineScreenState extends State<ConnectOnlineScreen> {
  final _code = TextEditingController();
  bool _signUp = true; // a new person on the server, until it says otherwise
  bool _sent = false, _busy = false;
  String? _errorKey, _noteKey;

  String t(String k) => tr(widget.lang, k);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _key(OtpResult r) => switch (r) {
        OtpResult.wrong => 'errOtpWrong',
        OtpResult.locked => 'errOtpLocked',
        OtpResult.offline => 'errOffline',
        _ => 'errOtpFailed',
      };

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    final r = await widget.otp.send(widget.phone, role: 'patient', signUp: _signUp);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == OtpResult.ok) {
        _sent = true;
      } else {
        _errorKey = _key(r);
      }
    });
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    final r = await widget.otp.verify(widget.phone, _code.text,
        role: 'patient', signUp: _signUp, name: widget.name);
    if (!mounted) return;
    if (r == OtpResult.accountExists || r == OtpResult.noAccount) {
      // This number is already known online (or is not): the code is used up,
      // so ask for a new one in the other mode.
      setState(() {
        _signUp = !_signUp;
        _sent = false;
        _busy = false;
        _code.clear();
        _noteKey = 'connectRetry';
      });
      return;
    }
    if (r != OtpResult.ok) {
      setState(() {
        _busy = false;
        _errorKey = _key(r);
      });
      return;
    }
    final user = widget.otp.serverUser;
    if (user != null) await widget.db.linkServerAccount(widget.accountId, user.id);
    if (!mounted) return;
    widget.onConnected();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('connectOnline'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(t('connectOnlineBody'), style: const TextStyle(fontSize: 16, height: 1.4)),
        const SizedBox(height: 14),
        Text(widget.phone,
            key: const ValueKey('connectPhone'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
        if (_noteKey != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(t(_noteKey!), style: const TextStyle(color: Palette.muted)),
          ),
        if (_sent) ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('connectCode'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(fontSize: 24, letterSpacing: 6),
            decoration: InputDecoration(labelText: t('enterOtp')),
          ),
        ],
        if (_errorKey != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t(_errorKey!),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('connectGo'),
          onPressed: _busy ? null : (_sent ? _verify : _send),
          child: Text(_sent ? t('verifyOtp') : t('sendOtp')),
        ),
      ]),
    );
  }
}
