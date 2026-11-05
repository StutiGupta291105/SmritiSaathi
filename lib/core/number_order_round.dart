import 'dart:math';

/// Number Order: tap the numbers from smallest to largest (or, at the top
/// level, largest to smallest). Level 1 to 3 use 1..4, 1..5, 1..6; level 4
/// uses six numbers up to 30; level 5 uses eight numbers up to 50, largest first.
class NumberOrderRound {
  NumberOrderRound(this.numbers, this.ascending);

  /// As laid out on screen.
  final List<int> numbers;
  final bool ascending;

  /// The order the person has to tap.
  List<int> get target {
    final s = [...numbers]..sort();
    return ascending ? s : s.reversed.toList();
  }

  int get columns => numbers.length <= 4 ? 2 : (numbers.length <= 9 ? 3 : 4);
}

NumberOrderRound generateNumberOrderRound(int level, Random rng) {
  final l = level.clamp(1, 5);
  List<int> nums;
  switch (l) {
    case 1:
      nums = [1, 2, 3, 4];
    case 2:
      nums = [1, 2, 3, 4, 5];
    case 3:
      nums = [1, 2, 3, 4, 5, 6];
    case 4:
      nums = _distinct(rng, 6, 30);
    default:
      nums = _distinct(rng, 8, 50);
  }
  nums.shuffle(rng);
  // Make sure the layout is not already in tap order.
  final asc = l < 5;
  final done = asc ? ([...nums]..sort()) : ([...nums]..sort((a, b) => b - a));
  var guard = 0;
  while (_equal(nums, done) && guard++ < 20) {
    nums.shuffle(rng);
  }
  return NumberOrderRound(nums, asc);
}

List<int> _distinct(Random rng, int n, int max) {
  final all = [for (var i = 1; i <= max; i++) i]..shuffle(rng);
  return all.take(n).toList();
}

bool _equal(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
