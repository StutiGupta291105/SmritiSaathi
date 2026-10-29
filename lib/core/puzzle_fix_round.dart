import 'dart:math';

import 'content.dart';

/// Puzzle Fix: a repeating pattern of pictures with one missing; pick the
/// piece that completes it. Level 1-3 repeat two pictures (then three at
/// level 3) and the gap is the last place; level 4-5 repeat three pictures,
/// the gap can be anywhere after the first repeat, and one wrong option is a
/// picture from the pattern itself, which is harder to rule out.
class PuzzleRound {
  PuzzleRound(this.sequence, this.missingAt, this.options, this.answerIndex);
  final List<Item> sequence; // complete, including the missing piece
  final int missingAt;
  final List<Item> options; // shuffled
  final int answerIndex;

  Item get answer => sequence[missingAt];
}

const kPuzzlePeriod = [2, 2, 3, 3, 3];
const kPuzzleLength = [5, 6, 7, 8, 9];
const kPuzzleOptions = [3, 3, 4, 4, 5];

PuzzleRound generatePuzzleRound(int level, Random rng) {
  final l = level.clamp(1, 5) - 1;
  final period = kPuzzlePeriod[l];
  final pool = [...kObjects]..shuffle(rng);
  final unit = pool.take(period).toList();
  final rest = pool.skip(period).toList();
  final length = kPuzzleLength[l];
  final sequence = [for (var i = 0; i < length; i++) unit[i % period]];
  final missing = l < 3
      ? length - 1
      : period + rng.nextInt(length - period); // after the first full repeat
  final answer = sequence[missing];

  final wrong = <Item>[];
  if (l >= 3) {
    wrong.add(unit.firstWhere((u) => u.emoji != answer.emoji));
  }
  for (final r in rest) {
    if (wrong.length >= kPuzzleOptions[l] - 1) break;
    wrong.add(r);
  }
  final options = [answer, ...wrong]..shuffle(rng);
  return PuzzleRound(
      sequence, missing, options, options.indexWhere((o) => o.emoji == answer.emoji));
}
