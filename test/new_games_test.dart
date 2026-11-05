import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/number_order_round.dart';
import 'package:smriti_assist/core/puzzle_fix_round.dart';
import 'package:smriti_assist/core/word_recall_round.dart';

void main() {
  final rng = Random(7);

  group('Number Order', () {
    test('sizes grow with level and the layout is never already solved', () {
      final sizes = [for (var l = 1; l <= 5; l++) generateNumberOrderRound(l, rng).numbers.length];
      expect(sizes, [4, 5, 6, 6, 8]);
      for (var l = 1; l <= 5; l++) {
        for (var i = 0; i < 50; i++) {
          final r = generateNumberOrderRound(l, rng);
          expect(r.numbers.toSet().length, r.numbers.length); // distinct
          expect(r.numbers, isNot(r.target), reason: 'level $l');
        }
      }
    });

    test('target order is ascending, except the top level which is descending', () {
      final low = generateNumberOrderRound(3, rng);
      expect(low.ascending, isTrue);
      expect(low.target, [1, 2, 3, 4, 5, 6]);
      final top = generateNumberOrderRound(5, rng);
      expect(top.ascending, isFalse);
      expect(top.target.first, greaterThan(top.target.last));
      expect(top.numbers.every((n) => n >= 1 && n <= 50), isTrue);
    });

    test('out-of-range levels are clamped', () {
      expect(generateNumberOrderRound(0, rng).numbers.length, 4);
      expect(generateNumberOrderRound(99, rng).numbers.length, 8);
    });
  });

  group('Word Recall', () {
    test('counts, time and distractors follow the level', () {
      for (var l = 1; l <= 5; l++) {
        final r = generateWordRecallRound(l, rng);
        expect(r.shown.length, kRecallCount[l - 1]);
        expect(r.seconds, kRecallSeconds[l - 1]);
        expect(r.options.length, r.shown.length * 2);
        expect(r.answerIndexes.length, r.shown.length);
      }
      expect(kRecallSeconds.first, greaterThan(kRecallSeconds.last));
    });

    test('options are unique and the answers are exactly the shown items', () {
      for (var i = 0; i < 100; i++) {
        final r = generateWordRecallRound(1 + i % 5, rng);
        expect(r.options.map((o) => o.emoji).toSet().length, r.options.length);
        final answers = r.answerIndexes.map((x) => r.options[x].emoji).toSet();
        expect(answers, r.shown.map((s) => s.emoji).toSet());
      }
    });
  });

  group('Puzzle Fix', () {
    test('the answer completes the repeating pattern and is unique among options', () {
      for (var i = 0; i < 200; i++) {
        final level = 1 + i % 5;
        final r = generatePuzzleRound(level, rng);
        final period = kPuzzlePeriod[level - 1];
        // the pattern really repeats
        for (var k = period; k < r.sequence.length; k++) {
          expect(r.sequence[k].emoji, r.sequence[k - period].emoji);
        }
        expect(r.options.length, kPuzzleOptions[level - 1]);
        expect(r.options.map((o) => o.emoji).toSet().length, r.options.length);
        expect(r.options[r.answerIndex].emoji, r.answer.emoji);
        expect(r.options.where((o) => o.emoji == r.answer.emoji).length, 1);
      }
    });

    test('the gap is last on easy levels and later in the pattern on hard ones', () {
      for (var i = 0; i < 50; i++) {
        final easy = generatePuzzleRound(2, rng);
        expect(easy.missingAt, easy.sequence.length - 1);
        final hard = generatePuzzleRound(5, rng);
        expect(hard.missingAt, greaterThanOrEqualTo(kPuzzlePeriod[4]));
        expect(hard.missingAt, lessThan(hard.sequence.length));
        // hard levels include a wrong option taken from the pattern itself
        final inPattern = hard.sequence.map((s) => s.emoji).toSet();
        expect(
            hard.options.where((o) => o.emoji != hard.answer.emoji && inPattern.contains(o.emoji)).length,
            greaterThanOrEqualTo(1));
      }
    });
  });
}
