import 'package:flutter/material.dart';

import 'languages.dart';
import 'strings.dart';
import 'theme.dart';
import 'ui.dart';

/// Active UI language, so text direction (right to left for Urdu, Kashmiri and
/// Sindhi) applies to the whole app, dialogs and sheets included.
final ValueNotifier<String> kActiveLanguage = ValueNotifier<String>('en');

/// Opens a scrolling list of every language, each in its own script with the
/// English name beneath (so it can be found even if the phone has no font for
/// that script). Returns the chosen code, or null if dismissed.
Future<String?> showLanguagePicker(BuildContext context,
    {required String current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Palette.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: Palette.line, borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(tr(current, 'chooseLanguage'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
          ),
        ),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              for (final code in kLanguageOrder)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    key: ValueKey('lang_$code'),
                    onTap: () => Navigator.pop(context, code),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(
                          code == current
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: code == current ? Palette.brand : Palette.muted),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(kLanguages[code]!,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                            Text(
                                kDraftLanguages.contains(code)
                                    ? '${kLanguageEnglish[code]!} · draft translation'
                                    : kLanguageEnglish[code]!,
                                style: const TextStyle(
                                    fontSize: 13, color: Palette.muted)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ]),
    ),
  );
}

/// A card showing the current language; tapping it opens [showLanguagePicker].
class LanguageRow extends StatelessWidget {
  const LanguageRow({
    super.key,
    required this.lang,
    required this.onChanged,
    this.accent = Palette.brand,
  });
  final String lang;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('languageRow'),
        onTap: () async {
          final picked = await showLanguagePicker(context, current: lang);
          if (picked != null && picked != lang) onChanged(picked);
        },
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          IconBadge(
              icon: Icons.language_rounded,
              fg: accent,
              bg: Palette.tileGreen,
              size: 44,
              circle: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kLanguages[lang] ?? lang,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                Text(kLanguageEnglish[lang] ?? '',
                    style:
                        const TextStyle(fontSize: 13, color: Palette.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 28, color: Palette.muted),
        ]),
      );
}
