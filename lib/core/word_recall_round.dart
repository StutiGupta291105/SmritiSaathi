import 'dart:math';

import 'content.dart';

/// Word Recall: look at a few pictures with their words, then pick the ones
/// that were shown from a larger set. Difficulty by level (1-5): 3, 3, 4, 4, 5
/// to remember, shown for 8, 7, 7, 6, 6 seconds, with as many look-alike or
/// unrelated distractors as there are items to remember.
class WordRecallRound {
  WordRecallRound(this.shown, this.options, this.seconds);
  final List<Item> shown;
  final List<Item> options; // shuffled: the shown items plus distractors
  final int seconds;

  Set<int> get answerIndexes => {
        for (var i = 0; i < options.length; i++)
          if (shown.any((s) => s.emoji == options[i].emoji)) i
      };
}

const kRecallCount = [3, 3, 4, 4, 5];
const kRecallSeconds = [8, 7, 7, 6, 6];

/// Everything that can appear, once each.
List<Item> recallPool() {
  final seen = <String>{};
  return [
    for (final i in [
      ...kObjects,
      for (final p in kLookAlikes) ...[p.$1, p.$2],
    ])
      if (seen.add(i.emoji)) i
  ];
}

WordRecallRound generateWordRecallRound(int level, Random rng) {
  final l = level.clamp(1, 5) - 1;
  final pool = recallPool()..shuffle(rng);
  final n = kRecallCount[l];
  final shown = pool.take(n).toList();
  final distract = pool.skip(n).take(n).toList();
  final options = [...shown, ...distract]..shuffle(rng);
  return WordRecallRound(shown, options, kRecallSeconds[l]);
}
