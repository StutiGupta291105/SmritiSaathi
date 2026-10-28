import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Games list: one white row per game with a coloured icon, title, one-line
/// description and a chevron, as on the design sheet.
class GamesTab extends StatelessWidget {
  const GamesTab({
    super.key,
    required this.lang,
    required this.onMemory,
    required this.onAttention,
    required this.onRoutine,
  });
  final String lang;
  final VoidCallback onMemory, onAttention, onRoutine;

  @override
  Widget build(BuildContext context) {
    String t(String k) => tr(lang, k);
    Widget row(IconData icon, Color fg, Color bg, String title, String desc,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AppCard(
            onTap: onTap,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconBadge(icon: icon, fg: fg, bg: bg, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      Text(desc,
                          style: const TextStyle(
                              fontSize: 14, color: Palette.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 32, color: Palette.muted),
              ],
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        ScreenTitle(t('cognitiveGames')),
        const SizedBox(height: 2),
        Text(t('chooseGame'),
            style: const TextStyle(fontSize: 15, color: Palette.muted)),
        const SizedBox(height: 18),
        row(Icons.grid_view_rounded, Palette.red, Palette.tileRed,
            t('memoryGame'), t('memoryGameDesc'), onMemory),
        row(Icons.center_focus_strong_rounded, Palette.green, Palette.tileGreen,
            t('gameAttention'), t('gameAttentionDesc'), onAttention),
        row(Icons.checklist_rounded, Palette.purple, Palette.tilePurple,
            t('gameRoutine'), t('gameRoutineDesc'), onRoutine),
      ],
    );
  }
}
