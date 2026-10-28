import 'dart:math';

import 'content.dart';

/// Daily-routine recall: put [shuffled] steps back in their usual order.
/// Level 1-5 asks for 3-7 consecutive steps of one routine (capped by the
/// length of the routines available).
class RoutineRound {
  RoutineRound(this.routine, this.ordered, this.shuffled);
  final Routine routine;
  final List<Item> ordered;
  final List<Item> shuffled;
}

RoutineRound generateRoutineRound(int level, Random rng) {
  final want = level.clamp(1, 5) + 2;
  final longest = kRoutines.map((r) => r.steps.length).reduce(max);
  final n = min(want, longest);
  final eligible = kRoutines.where((r) => r.steps.length >= n).toList();
  final routine = eligible[rng.nextInt(eligible.length)];
  final start = rng.nextInt(routine.steps.length - n + 1);
  final ordered = routine.steps.sublist(start, start + n);
  var shuffled = [...ordered]..shuffle(rng);
  while (n > 1 && _same(shuffled, ordered)) {
    shuffled = [...ordered]..shuffle(rng);
  }
  return RoutineRound(routine, ordered, shuffled);
}

bool _same(List<Item> a, List<Item> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i].emoji != b[i].emoji || a[i].en != b[i].en) return false;
  }
  return true;
}
