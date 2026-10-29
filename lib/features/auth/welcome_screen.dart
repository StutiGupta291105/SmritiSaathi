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
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Palette.brand,
                      elevation: 3,
                      shadowColor: const Color(0x33000000),
                    ),
                    onPressed: onGetStarted,
                    child: Text(t('getStarted')),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: onLogin,
                    child: Text(t('login'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Palette.brand)),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    t('chooseLanguage'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Palette.brandDeep),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final e in kLanguages.entries)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                left: e.key == kLanguages.keys.first ? 0 : 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onLangChanged(e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 2),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: lang == e.key
                                      ? Palette.action
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: lang == e.key
                                          ? Palette.action
                                          : Palette.line),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    e.value,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: lang == e.key
                                          ? Colors.white
                                          : Palette.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
