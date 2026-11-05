import 'package:flutter/material.dart';

/// Every game, in the order shown on the Games list. [id] is what is stored
/// with each session and sent to the server.
class GameInfo {
  const GameInfo(this.id, this.titleKey, this.descKey, this.icon, this.color);
  final String id, titleKey, descKey;
  final IconData icon;

  /// Solid colour of the rounded icon square.
  final Color color;
}

const kGames = [
  GameInfo('faces', 'gameFaces', 'gameFacesDesc',
      Icons.face_retouching_natural_rounded, Color(0xFFA477E1)),
  GameInfo('echo', 'gameEcho', 'gameEchoDesc',
      Icons.graphic_eq_rounded, Color(0xFF3196F1)),
  GameInfo('where', 'gameWhere', 'gameWhereDesc',
      Icons.grid_view_rounded, Color(0xFFF26B5E)),
  GameInfo('change', 'gameChange', 'gameChangeDesc',
      Icons.compare_rounded, Color(0xFFF2A63B)),
  GameInfo('sort', 'gameSort', 'gameSortDesc',
      Icons.category_rounded, Color(0xFF69B64C)),
  GameInfo('tile', 'gameTile', 'gameTileDesc',
      Icons.dashboard_customize_rounded, Color(0xFF1F8B68)),
];

/// Games that were replaced. Their saved sessions stay in the history and
/// keep their names, but they can no longer be played.
const kLegacyGameTitles = {
  'memory_match': 'memoryGame',
  'word_recall': 'gameWordRecall',
  'puzzle_fix': 'gamePuzzleFix',
  'number_order': 'gameNumberOrder',
  'attention': 'gameAttention',
  'routine': 'gameRoutine',
};

final kGameIds = [for (final g in kGames) g.id];

/// Title key for a stored game id, old or new.
String gameTitleKey(String id) {
  for (final g in kGames) {
    if (g.id == id) return g.titleKey;
  }
  return kLegacyGameTitles[id] ?? kGames.first.titleKey;
}

/// Look up a game for its icon and colour; old ids get a neutral look.
GameInfo gameInfoFor(String id) => kGames.firstWhere((g) => g.id == id,
    orElse: () => GameInfo(id, gameTitleKey(id), '', Icons.extension_rounded,
        const Color(0xFF8B96A5)));
