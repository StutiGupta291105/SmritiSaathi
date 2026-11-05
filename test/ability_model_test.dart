import 'package:flutter_test/flutter_test.dart';
import 'package:smriti_assist/core/ability_model.dart';
import 'package:smriti_assist/core/adaptive_engine.dart';

void main() {
  test('with no data the model recommends exactly the caregiver baseline', () {
    for (var b = 1; b <= 5; b++) {
      final m = AbilityModel.fit(stats: const [], baseline: b);
      expect(m.recommend(DifficultyBand(b)), b);
    }
  });

  test('consistently perfect play at the top of the band raises the start level',
      () {
    final m = AbilityModel.fit(
        stats: const [LevelStat(3, 40, 40)], baseline: 2);
    expect(m.recommend(const DifficultyBand(2)), 3);
  });

  test('consistently poor play lowers the start level, within the band', () {
    final m = AbilityModel.fit(
        stats: const [LevelStat(2, 40, 10)], baseline: 2);
    expect(m.recommend(const DifficultyBand(2)), 1);
  });

  test('recommendation never leaves the caregiver band', () {
    final great = AbilityModel.fit(
        stats: const [LevelStat(5, 200, 200)], baseline: 3);
    expect(great.recommend(const DifficultyBand(3)), 4); // band is 2..4
    final awful = AbilityModel.fit(
        stats: const [LevelStat(1, 200, 0)], baseline: 3);
    expect(awful.recommend(const DifficultyBand(3)), 2);
  });

  test('predicted success falls as level rises', () {
    final m = AbilityModel.fit(
        stats: const [LevelStat(2, 20, 15), LevelStat(3, 20, 10)], baseline: 3);
    for (var l = 1; l < 5; l++) {
      expect(m.predict(l), greaterThan(m.predict(l + 1)));
    }
  });

  test('a little data moves the estimate less than a lot of data', () {
    final little = AbilityModel.fit(
        stats: const [LevelStat(3, 4, 4)], baseline: 2);
    final lots = AbilityModel.fit(
        stats: const [LevelStat(3, 80, 80)], baseline: 2);
    expect(lots.theta, greaterThan(little.theta));
    expect(little.trials, 4);
  });

  test('engine records per-level tallies as JSON', () {
    final e = AdaptiveEngine(band: const DifficultyBand(2));
    e.recordTrial(correct: true, responseMs: 1000);
    e.recordTrial(correct: false, responseMs: 1000);
    expect(e.levelStats[2], [2, 1]);
    expect(e.levelStatsJson(), '{"2":[2,1]}');
  });
}
