import 'package:flutter/material.dart';

import '../../core/games.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Games list: one white row per game with a solid coloured icon square, title,
/// one-line description and a chevron, as on the design sheet.
class GamesTab extends StatelessWidget {
  const GamesTab({super.key, required this.lang, required this.onPlay});
  final String lang;

  /// Called with the game's id (see [kGames]).
  final void Function(String id) onPlay;

  @override
  Widget build(BuildContext context) {
    String t(String k) => tr(lang, k);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        ScreenTitle(t('cognitiveGames')),
        const SizedBox(height: 2),
        Text(t('chooseGame'),
            style: const TextStyle(fontSize: 14, color: Palette.muted)),
        const SizedBox(height: 16),
        for (final g in kGames)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              onTap: () => onPlay(g.id),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: g.color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(g.icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(g.titleKey),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Palette.brandDeep)),
                        Text(t(g.descKey),
                            style: const TextStyle(
                                fontSize: 13, color: Palette.muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 26, color: Palette.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
