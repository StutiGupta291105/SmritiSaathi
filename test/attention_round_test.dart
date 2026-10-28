import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/attention_round.dart';

void main() {
  test('grid grows with level; exactly one cell differs from all the others', () {
    final rng = Random(1);
    for (var level = 1; level <= 5; level++) {
      for (var i = 0; i < 50; i++) {
        final r = generateAttentionRound(level, rng);
        expect(r.cells.length, kAttentionCells[level - 1]);
        final target = r.cells[r.targetIndex];
        final others = [
          for (var j = 0; j < r.cells.length; j++)
            if (j != r.targetIndex) r.cells[j].emoji
        ];
        expect(others.toSet().length, 1);
        expect(others.first, isNot(target.emoji));
      }
    }
  });

  test('level 5 uses a 4x4 grid', () {
    final r = generateAttentionRound(5, Random(2));
    expect(r.columns, 4);
    expect(r.cells.length, 16);
  });
}
