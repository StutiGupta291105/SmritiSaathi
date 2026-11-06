import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'garden_frame.dart';

/// First screen: the Sunrise Garden, the promise in one line, then Create account or Log in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.lang,
    required this.onGetStarted,
    required this.onLogin,
    this.onLangChanged,
  });
  final String lang;
  final VoidCallback onGetStarted, onLogin;
  final ValueChanged<String>? onLangChanged;

  String t(String k) => tr(lang, k);

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      lang: lang,
      title: t('tagline'),
      subtitle: t('welcomeBody'),
      heroHeight: 250,
      growth: 1,
      onLangChanged: onLangChanged,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(
          key: const ValueKey('getStarted'),
          onPressed: onGetStarted,
          child: Text(t('createAccount')),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const ValueKey('welcomeLogin'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            foregroundColor: Palette.brand,
            side: const BorderSide(color: Palette.brand, width: 1.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(
                fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w600),
          ),
          onPressed: onLogin,
          child: Text(t('login')),
        ),
      ]),
    );
  }
}
