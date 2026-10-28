import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/routine_round.dart';

void main() {
  test('step count follows level and is a consecutive slice in order', () {
    final rng = Random(3);
    for (var level = 1; level <= 5; level++) {
      for (var i = 0; i < 50; i++) {
        final r = generateRoutineRound(level, rng);
        expect(r.ordered.length, level + 2);
        expect(r.shuffled.length, r.ordered.length);
        final steps = r.routine.steps;
        final start = steps.indexWhere((s) => s.en == r.ordered.first.en);
        for (var k = 0; k < r.ordered.length; k++) {
          expect(steps[start + k].en, r.ordered[k].en);
        }
      }
    }
  });

  test('shuffled order is never already the correct order', () {
    final rng = Random(4);
    for (var i = 0; i < 100; i++) {
      final r = generateRoutineRound(1, rng);
      final same = List.generate(r.ordered.length,
          (k) => r.ordered[k].en == r.shuffled[k].en).every((b) => b);
      expect(same, isFalse);
    }
  });
}
