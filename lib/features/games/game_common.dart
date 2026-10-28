import '../../core/adaptive_engine.dart';
import '../../data/app_database.dart';

/// Stores a finished session. If consent was withdrawn mid-play the game still
/// works but nothing is stored (DPDP: no processing without consent).
Future<void> saveGameSession({
  required AppDatabase db,
  required String patientId,
  required String game,
  required DateTime startedAt,
  required int startLevel,
  required AdaptiveEngine engine,
}) async {
  if (engine.trials == 0) return;
  try {
    await db.insertSession(
      patientId: patientId,
      game: game,
      startedAt: startedAt,
      startLevel: startLevel,
      endLevel: engine.level,
      trials: engine.trials,
      correct: engine.correctTrials,
    );
  } on ConsentRequired {
    // Intentionally ignored.
  }
}
