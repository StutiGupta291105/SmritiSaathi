import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/game_rounds.dart';

void main() {
  final rng = Random(7);
  test('faces: studied people include the asked one, options are unique names', () {
    for (var l = 1; l <= 5; l++) {
      for (var i = 0; i < 30; i++) {
        final r = generateFaceRound(l, const [Person('Mohan', '👴'), Person('Mohan', '👴')], rng);
        expect(r.shown.length, facesToStudy(l));
        expect(r.shown, contains(r.asked));
        expect(r.options.length, faceOptions(l));
        expect(r.options.toSet().length, r.options.length);
        expect(r.options, contains(r.asked.name));
      }
    }
  });
  test('faces: family members come first when there are enough', () {
    const fam = [Person('A1', '👩'), Person('B2', '👨'), Person('C3', '👵'), Person('D4', '👴')];
    final r = generateFaceRound(5, fam, rng);
    expect(r.shown.every(fam.contains), isTrue);
  });
  test('echo: lengths grow, no tile three times in a row', () {
    for (var l = 1; l <= 5; l++) {
      final s = generateEchoSequence(l, rng);
      expect(s.length, l + 2);
      expect(s.every((n) => n < echoTiles(l)), isTrue);
      for (var i = 2; i < s.length; i++) {
        expect(s[i] == s[i - 1] && s[i] == s[i - 2], isFalse);
      }
    }
  });
  test('where: the asked cell holds an object and cells fit the grid', () {
    for (var l = 1; l <= 5; l++) {
      final r = generateWhereRound(l, rng);
      expect(r.placed.length, whereObjects(l));
      expect(r.placed.containsKey(r.asked), isTrue);
      expect(r.placed.keys.every((c) => c < r.rows * r.cols), isTrue);
      expect(r.placed.values.toSet().length, r.placed.length);
    }
  });
  test('change: exactly one item differs', () {
    for (var l = 1; l <= 5; l++) {
      for (var i = 0; i < 30; i++) {
        final r = generateChangeRound(l, rng);
        var diff = 0;
        for (var k = 0; k < r.before.length; k++) {
          if (r.before[k] != r.after[k]) diff++;
        }
        expect(diff, 1);
        expect(r.before[r.changed] != r.after[r.changed], isTrue);
        expect(r.before.toSet().length, r.before.length);
      }
    }
  });
  test('sort: the answer is among the choices and matches the item', () {
    for (var l = 1; l <= 5; l++) {
      final r = generateSortRound(l, rng);
      expect(r.choices.length, sortCategories(l));
      expect(r.choices, contains(r.answer));
      expect(kSortItems[r.answer], contains(r.item));
    }
  });
  test('order: shuffled differs from the right order and has the same steps', () {
    for (var l = 4; l <= 5; l++) {
      for (var i = 0; i < 30; i++) {
        final o = generateOrderRound(l, rng);
        expect(o.right.length, orderSteps(l));
        expect(o.shuffled.toSet(), o.right.toSet());
        expect(o.shuffled.join(), isNot(o.right.join()));
        expect(o.right.first, kMorningSteps.first);
      }
    }
  });
  test('tiles: every face appears exactly twice', () {
    for (var l = 1; l <= 5; l++) {
      final b = generateTileBoard(l, rng);
      expect(b.length, tilePairs(l) * 2);
      final counts = <String, int>{};
      for (final f in b) {
        counts.update('${f.icon}/${f.colorIndex}', (n) => n + 1, ifAbsent: () => 1);
      }
      expect(counts.values.every((n) => n == 2), isTrue);
      expect(b.length <= tileColumns(l) * 4, isTrue);
    }
  });
}
