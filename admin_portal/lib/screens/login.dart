import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen(
      {super.key,
      required this.apiFactory,
      required this.onSignedIn,
      this.notice = ''});
  final AdminApi Function(String baseUrl) apiFactory;
  final void Function(AdminApi api) onSignedIn;
  final String notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server =
      TextEditingController(text: 'https://smriti-api-227e.onrender.com');
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String _error = '';

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final api = widget.apiFactory(_server.text.trim());
    try {
      await api.login(_user.text.trim(), _pass.text, _code.text.trim());
      if (mounted) widget.onSignedIn(api);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c,
            {bool secret = false, Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: key,
            controller: c,
            obscureText: secret,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true),
            onSubmitted: (_) => _busy ? null : _go(),
          ),
        );
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: Panel(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Smriti Sathi Admin',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Pal.ink)),
                  const SizedBox(height: 4),
                  const Text(
                      'Read-only monitoring. Nothing here can change app data.',
                      style: TextStyle(color: Pal.muted, fontSize: 13)),
                  const SizedBox(height: 18),
                  if (widget.notice.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(widget.notice,
                          style: const TextStyle(color: Pal.warn)),
                    ),
                  field('Server address', _server,
                      key: const ValueKey('server')),
                  field('Username', _user, key: const ValueKey('username')),
                  field('Password', _pass,
                      secret: true, key: const ValueKey('password')),
                  field('Authenticator code (only if switched on)', _code,
                      key: const ValueKey('code')),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error,
                          key: const ValueKey('loginError'),
                          style: const TextStyle(color: Pal.bad)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('signIn'),
                      onPressed: _busy ? null : _go,
                      child: Text(_busy ? 'Signing in…' : 'Sign in'),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}
