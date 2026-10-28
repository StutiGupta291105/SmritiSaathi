import 'dart:math';

import 'content.dart';

/// One "find the one that is different" trial. Difficulty by level (1-5):
/// grid grows from 4 to 16 cells, and from level 4 the odd one out is a
/// look-alike (marigold vs sunflower) instead of a clearly different object.
class AttentionRound {
  AttentionRound(this.cells, this.targetIndex, this.columns);
  final List<Item> cells;
  final int targetIndex;
  final int columns;
}

const kAttentionCells = [4, 6, 9, 12, 16];
const kAttentionColumns = [2, 3, 3, 4, 4];

AttentionRound generateAttentionRound(int level, Random rng) {
  final l = level.clamp(1, 5) - 1;
  final n = kAttentionCells[l];
  late final Item common, odd;
  if (level >= 4) {
    final pair = kLookAlikes[rng.nextInt(kLookAlikes.length)];
    final swap = rng.nextBool();
    common = swap ? pair.$1 : pair.$2;
    odd = swap ? pair.$2 : pair.$1;
  } else {
    final pool = [...kObjects]..shuffle(rng);
    common = pool[0];
    odd = pool[1];
  }
  final target = rng.nextInt(n);
  final cells = List<Item>.generate(n, (i) => i == target ? odd : common);
  return AttentionRound(cells, target, kAttentionColumns[l]);
}
