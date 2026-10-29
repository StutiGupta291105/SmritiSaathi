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
  GameInfo('memory_match', 'memoryGame', 'memoryGameDesc',
      Icons.grid_view_rounded, Color(0xFFF26B5E)),
  GameInfo('word_recall', 'gameWordRecall', 'gameWordRecallDesc',
      Icons.psychology_alt_rounded, Color(0xFF1F8B68)),
  GameInfo('puzzle_fix', 'gamePuzzleFix', 'gamePuzzleFixDesc',
      Icons.extension_rounded, Color(0xFFA477E1)),
  GameInfo('number_order', 'gameNumberOrder', 'gameNumberOrderDesc',
      Icons.pin_rounded, Color(0xFF3196F1)),
  GameInfo('attention', 'gameAttention', 'gameAttentionDesc',
      Icons.center_focus_strong_rounded, Color(0xFF69B64C)),
  GameInfo('routine', 'gameRoutine', 'gameRoutineDesc',
      Icons.checklist_rounded, Color(0xFFF2A63B)),
];

final kGameIds = [for (final g in kGames) g.id];

/// Title key for a stored game id (falls back to the memory game's).
String gameTitleKey(String id) =>
    kGames.firstWhere((g) => g.id == id, orElse: () => kGames.first).titleKey;
