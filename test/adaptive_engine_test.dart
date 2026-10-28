import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/adaptive_engine.dart';

void main() {
  group('DifficultyBand', () {
    test('is baseline +/-1, clamped to 1..5', () {
      expect(const DifficultyBand(3).min, 2);
      expect(const DifficultyBand(3).max, 4);
      expect(const DifficultyBand(1).min, 1);
      expect(const DifficultyBand(5).max, 5);
    });
  });

  group('AdaptiveEngine', () {
    test('starts at the caregiver baseline', () {
      expect(AdaptiveEngine(band: const DifficultyBand(3)).level, 3);
    });

    test('steps up after 3 fast correct answers, within band', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      e.recordTrial(correct: true, responseMs: 1000);
      e.recordTrial(correct: true, responseMs: 1000);
      expect(e.recordTrial(correct: true, responseMs: 1000), LevelChange.up);
      expect(e.level, 4);
    });

    test('never exceeds the band ceiling', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      for (var i = 0; i < 30; i++) {
        e.recordTrial(correct: true, responseMs: 500);
      }
      expect(e.level, 4);
    });

    test('steps down after 2 misses, never below the band floor', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      e.recordTrial(correct: false, responseMs: 500);
      expect(e.recordTrial(correct: false, responseMs: 500), LevelChange.down);
      expect(e.level, 2);
      for (var i = 0; i < 30; i++) {
        e.recordTrial(correct: false, responseMs: 500);
      }
      expect(e.level, 2);
    });

    test('slow correct answers do not count toward stepping up', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      for (var i = 0; i < 10; i++) {
        e.recordTrial(correct: true, responseMs: 20000);
      }
      expect(e.level, 3);
    });

    test('a miss resets the good streak', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      e.recordTrial(correct: true, responseMs: 500);
      e.recordTrial(correct: true, responseMs: 500);
      e.recordTrial(correct: false, responseMs: 500);
      e.recordTrial(correct: true, responseMs: 500);
      expect(e.level, 3);
    });

    test('tracks accuracy', () {
      final e = AdaptiveEngine(band: const DifficultyBand(3));
      e.recordTrial(correct: true, responseMs: 500);
      e.recordTrial(correct: false, responseMs: 500);
      expect(e.accuracy, 0.5);
    });
  });

  group('suggestBaseline', () {
    const band = DifficultyBand(3);

    test('suggests raise when last 3 sessions ended at the ceiling', () {
      expect(
        suggestBaseline(band: band, recentSessionEndLevels: [3, 4, 4, 4]),
        BaselineSuggestion.raise,
      );
    });

    test('suggests lower when last 3 sessions ended at the floor', () {
      expect(
        suggestBaseline(band: band, recentSessionEndLevels: [2, 2, 2]),
        BaselineSuggestion.lower,
      );
    });

    test('no suggestion with too little data or mixed results', () {
      expect(
        suggestBaseline(band: band, recentSessionEndLevels: [4, 4]),
        BaselineSuggestion.none,
      );
      expect(
        suggestBaseline(band: band, recentSessionEndLevels: [4, 3, 4]),
        BaselineSuggestion.none,
      );
    });

    test('no raise suggestion when baseline is already the maximum', () {
      expect(
        suggestBaseline(
          band: const DifficultyBand(5),
          recentSessionEndLevels: [5, 5, 5],
        ),
        BaselineSuggestion.none,
      );
    });
  });
}
