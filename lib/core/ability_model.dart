import 'dart:math';

import 'adaptive_engine.dart';

/// Trials and correct answers at one difficulty level.
class LevelStat {
  const LevelStat(this.level, this.trials, this.correct);
  final int level, trials, correct;
}

double _sigmoid(double x) => 1 / (1 + exp(-x));

/// On-device learned difficulty model: a one-parameter logistic (Rasch style)
/// model, P(correct | level) = sigmoid(k * (theta - level)), where theta is the
/// person's current ability on the 1-5 level scale.
///
/// theta is estimated by maximum a posteriori fitting over the person's own
/// history, with a prior centred where the caregiver's baseline gives
/// [targetSuccess]. With no data the model therefore recommends exactly the
/// baseline; with data it moves toward the level that gives about
/// [targetSuccess] correct answers (challenging but not discouraging).
///
/// It never leaves the caregiver's band: [recommend] clamps to it. Nothing
/// here is a clinical measure; it describes game performance only.
class AbilityModel {
  AbilityModel._(this.theta, this.trials);

  static const double slope = 1.2;
  static const double priorSd = 1.0;
  static const double targetSuccess = 0.75;

  /// Estimated ability on the level scale.
  final double theta;

  /// How many trials the estimate is based on.
  final int trials;

  static double _priorMean(int baseline) =>
      baseline + log(targetSuccess / (1 - targetSuccess)) / slope;

  static AbilityModel fit({
    required List<LevelStat> stats,
    required int baseline,
  }) {
    final prior = _priorMean(baseline);
    var theta = prior;
    final total = stats.fold<int>(0, (n, s) => n + s.trials);
    for (var i = 0; i < 30; i++) {
      var grad = -(theta - prior) / (priorSd * priorSd);
      var hess = -1 / (priorSd * priorSd);
      for (final s in stats) {
        final p = _sigmoid(slope * (theta - s.level));
        grad += slope * (s.correct - s.trials * p);
        hess -= slope * slope * s.trials * p * (1 - p);
      }
      final step = grad / hess;
      theta = (theta - step).clamp(0.0, 7.0);
      if (step.abs() < 1e-7) break;
    }
    return AbilityModel._(theta, total);
  }

  /// Predicted chance of a correct answer at [level].
  double predict(int level) => _sigmoid(slope * (theta - level));

  /// The level inside [band] whose predicted success is closest to
  /// [targetSuccess] (the gentler level on a tie).
  int recommend(DifficultyBand band) {
    var best = band.min;
    var bestGap = double.infinity;
    for (var l = band.min; l <= band.max; l++) {
      final gap = (predict(l) - targetSuccess).abs();
      if (gap < bestGap - 1e-9) {
        best = l;
        bestGap = gap;
      }
    }
    return best;
  }
}
