import 'package:flutter/material.dart';

import '../../core/languages.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// First screen: scenic header, brand, Get Started / Login, language choice.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.lang,
    required this.onLangChanged,
    required this.onGetStarted,
    required this.onLogin,
  });
  final String lang;
  final ValueChanged<String> onLangChanged;
  final VoidCallback onGetStarted, onLogin;

  String t(String k) => tr(lang, k);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                children: [
                  BrandLogo(size: 1.1, subtitle: t('brandSub')),
                  const SizedBox(height: 16),
                  Text(
                    t('tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Palette.brandDeep,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('welcomeBody'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Palette.muted),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: onGetStarted,
                    child: Text(t('getStarted')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: onLogin, child: Text(t('login'))),
                  const SizedBox(height: 24),
                  Text(
                    t('chooseLanguage'),
                    style: const TextStyle(fontSize: 14, color: Palette.muted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final e in kLanguages.entries)
                        ChoiceChip(
                          label: Text(
                            e.value,
                            style: const TextStyle(fontSize: 18),
                          ),
                          selected: lang == e.key,
                          selectedColor: Palette.action,
                          labelStyle: TextStyle(
                            color: lang == e.key ? Colors.white : Palette.ink,
                          ),
                          showCheckmark: false,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          onSelected: (_) => onLangChanged(e.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
