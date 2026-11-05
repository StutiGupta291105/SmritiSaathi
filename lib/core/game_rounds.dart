/// Round generators for the six memory games. Pure functions of the level
/// (1..5) and a random source, so they can be tested without a screen.
library;

import 'dart:math';

// ---- Who Is This? (faces and names) ---------------------------------------

class Person {
  const Person(this.name, this.emoji, {this.photo});
  final String name;
  final String emoji; // shown when there is no photo
  final List<int>? photo;
}

/// People used when the family list is too short to play with.
const kSamplePeople = [
  Person('Asha', '👩'),
  Person('Ravi', '👨'),
  Person('Meena', '👵'),
  Person('Arjun', '🧑'),
  Person('Sita', '👧'),
  Person('Kiran', '👦'),
  Person('Gopal', '👴'),
  Person('Lata', '👩‍🦳'),
];

class FaceRound {
  const FaceRound(this.shown, this.asked, this.options);
  final List<Person> shown; // studied together
  final Person asked; // one of [shown]
  final List<String> options; // names, includes the right one
}

int facesToStudy(int level) => const [2, 2, 3, 3, 4][level - 1];
int faceOptions(int level) => const [2, 3, 3, 4, 4][level - 1];

/// Seconds the faces stay on screen.
int faceStudySeconds(int level) => const [8, 7, 7, 6, 6][level - 1];

FaceRound generateFaceRound(int level, List<Person> family, Random rng) {
  final seen = <String>{};
  final pool = <Person>[];
  for (final p in [...family, ...kSamplePeople]) {
    if (p.name.trim().isEmpty) continue;
    if (seen.add(p.name.trim().toLowerCase())) pool.add(p);
  }
  // Family first, but shuffled, so repeats are not predictable.
  final fam = pool.where((p) => family.contains(p)).toList()..shuffle(rng);
  final rest = pool.where((p) => !family.contains(p)).toList()..shuffle(rng);
  final ordered = [...fam, ...rest];
  final shown = ordered.take(facesToStudy(level)).toList()..shuffle(rng);
  final asked = shown[rng.nextInt(shown.length)];
  final others = [for (final p in ordered) if (p != asked) p.name]..shuffle(rng);
  final options = [asked.name, ...others.take(faceOptions(level) - 1)]..shuffle(rng);
  return FaceRound(shown, asked, options);
}

// ---- Sequence Echo --------------------------------------------------------

int echoTiles(int level) => level >= 4 ? 6 : 4;
int echoLength(int level) => level + 2; // 3..7

List<int> generateEchoSequence(int level, Random rng) {
  final tiles = echoTiles(level);
  final seq = <int>[];
  for (var i = 0; i < echoLength(level); i++) {
    // Avoid the same tile three times running: hard to count and not fun.
    var n = rng.nextInt(tiles);
    while (seq.length >= 2 && seq[seq.length - 1] == n && seq[seq.length - 2] == n) {
      n = rng.nextInt(tiles);
    }
    seq.add(n);
  }
  return seq;
}

// ---- Where Did It Go? -----------------------------------------------------

const kObjects = ['☕', '🔑', '👓', '📖', '🍎', '🌻', '⏰', '🧦', '🎈', '🐦', '🥛', '🧺'];

class WhereRound {
  const WhereRound(this.rows, this.cols, this.placed, this.asked);
  final int rows, cols;
  final Map<int, String> placed; // cell index -> object
  final int asked; // cell index of the object we ask for
}

int whereObjects(int level) => const [2, 3, 3, 4, 5][level - 1];
int whereStudySeconds(int level) => const [6, 6, 5, 5, 5][level - 1];

WhereRound generateWhereRound(int level, Random rng) {
  final rows = level <= 2 ? 2 : 3, cols = 3;
  final cells = List<int>.generate(rows * cols, (i) => i)..shuffle(rng);
  final objects = [...kObjects]..shuffle(rng);
  final n = whereObjects(level);
  final placed = {for (var i = 0; i < n; i++) cells[i]: objects[i]};
  final asked = placed.keys.elementAt(rng.nextInt(n));
  return WhereRound(rows, cols, placed, asked);
}

// ---- Spot the Change ------------------------------------------------------

const kSceneItems = [
  '🌳', '🏠', '☀️', '🐕', '🚲', '🌷', '🦋', '🧺', '⛲', '🐓', '🪁', '🍎', '🐄', '🛖', '🌈', '🐝'
];

class ChangeRound {
  const ChangeRound(this.before, this.after, this.changed);
  final List<String> before, after;
  final int changed; // index that differs
}

int changeItems(int level) => const [4, 6, 6, 8, 9][level - 1];
int changeColumns(int level) => const [2, 3, 3, 4, 3][level - 1];
int changeStudySeconds(int level) => const [8, 8, 7, 7, 7][level - 1];

ChangeRound generateChangeRound(int level, Random rng) {
  final pool = [...kSceneItems]..shuffle(rng);
  final n = changeItems(level);
  final before = pool.take(n).toList();
  final after = [...before];
  final i = rng.nextInt(n);
  after[i] = pool[n]; // an item that was not in the picture
  return ChangeRound(before, after, i);
}

// ---- Sort the Day ---------------------------------------------------------

enum SortCategory { food, wear, animal }

const kSortItems = {
  SortCategory.food: ['🍎', '🍌', '🥕', '🍞', '🍚', '🥛', '🍋', '🥔'],
  SortCategory.wear: ['👕', '🧦', '👗', '🧢', '🧥', '👟', '🧣', '👖'],
  SortCategory.animal: ['🐄', '🐕', '🐈', '🐓', '🐘', '🐑', '🐎', '🐐'],
};

int sortCategories(int level) => level <= 2 ? 2 : 3;

class SortRound {
  const SortRound(this.item, this.answer, this.choices);
  final String item;
  final SortCategory answer;
  final List<SortCategory> choices;
}

SortRound generateSortRound(int level, Random rng) {
  final cats = [...SortCategory.values]..shuffle(rng);
  final choices = cats.take(sortCategories(level)).toList();
  final answer = choices[rng.nextInt(choices.length)];
  final items = kSortItems[answer]!;
  return SortRound(items[rng.nextInt(items.length)], answer, choices);
}

/// Morning steps in the order people usually do them.
const kMorningSteps = ['🛏️', '🪥', '🚿', '👕', '🍳', '☕', '💊'];

int orderSteps(int level) => level >= 5 ? 5 : 4;

/// The steps for an ordering round, in the right order, and a shuffled copy.
({List<String> right, List<String> shuffled}) generateOrderRound(int level, Random rng) {
  final n = orderSteps(level);
  // Always starts with waking up so the order is unambiguous.
  final rest = kMorningSteps.sublist(1);
  final start = rng.nextInt(rest.length - n + 2);
  final right = [kMorningSteps.first, ...rest.sublist(start, start + n - 1)];
  var shuffled = [...right]..shuffle(rng);
  while (shuffled.length > 1 && _same(shuffled, right)) {
    shuffled = [...right]..shuffle(rng);
  }
  return (right: right, shuffled: shuffled);
}

bool _same(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---- Match the Tile -------------------------------------------------------

class TileFace {
  const TileFace(this.icon, this.colorIndex);
  final int icon, colorIndex; // indexes into the screen's icon and colour lists
}

/// Pairs on the board: 3, 4, 6, 6, 8.
int tilePairs(int level) => const [3, 4, 6, 6, 8][level - 1];
int tileColumns(int level) => const [3, 4, 4, 4, 4][level - 1];

/// Seconds the whole board is shown face-up at the start (0 = none).
int tilePeekSeconds(int level) => const [4, 3, 2, 1, 0][level - 1];

/// A shuffled board: each face appears exactly twice.
List<TileFace> generateTileBoard(int level, Random rng, {int icons = 12, int colors = 6}) {
  final all = [for (var i = 0; i < icons; i++) i]..shuffle(rng);
  final faces = <TileFace>[];
  for (var i = 0; i < tilePairs(level); i++) {
    final f = TileFace(all[i], i % colors);
    faces..add(f)..add(f);
  }
  faces.shuffle(rng);
  return faces;
}
