import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/progression.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';
import 'game_ui.dart';

/// What every game needs from the app.
abstract class RoundGame extends StatefulWidget {
  const RoundGame({
    super.key,
    required this.db,
    required this.patientId,
    required this.baselineLevel,
    required this.startLevel,
    required this.language,
    required this.voice,
    required this.voiceOn,
  });
  final AppDatabase db;
  final String patientId;
  final int baselineLevel, startLevel;
  final String language;
  final Voice voice;
  final bool voiceOn;
}

/// Shared play loop: a fixed number of rounds at one level, a gentle "well
/// done" after each, a saved session, and a closing card that says whether the
/// level was cleared and how close the next level is.
///
/// The level does not change during a play; [gameProgress] moves it between
/// plays (same level for three clears, then a little harder).
abstract class RoundGameState<W extends RoundGame> extends State<W> {
  String get gameId;
  String get titleKey;
  String get descKey;
  int get rounds => 5;

  /// Called at the start and after each finished round.
  void beginRound();

  /// The playing area (inside the common frame).
  Widget buildPlay(BuildContext context);

  late final AdaptiveEngine engine;
  late final int startLevel;
  final DateTime sessionStart = DateTime.now();
  final rng = Random();
  final sw = Stopwatch();
  final List<Timer> _timers = [];

  int done = 0; // finished rounds
  bool locked = false; // input off while feedback shows
  bool? feedback; // true = right, false = not this time
  bool _finishing = false;

  String t(String k) => tr(widget.language, k);
  int get level => engine.level;
  String get roundText => trf(widget.language, 'roundOf', a: done + 1, b: rounds);

  @override
  void initState() {
    super.initState();
    // The level is fixed for the whole play (no staircase inside it).
    engine = AdaptiveEngine(
        band: DifficultyBand(widget.baselineLevel),
        startLevel: widget.startLevel,
        upAfter: 1 << 20,
        downAfter: 1 << 20);
    startLevel = engine.level;
    beginRound();
    sw
      ..reset()
      ..start();
  }

  /// A timer that is cancelled with the screen.
  Timer after(Duration d, VoidCallback f) {
    final timer = Timer(d, () {
      if (mounted) f();
    });
    _timers.add(timer);
    return timer;
  }

  void say(String text) =>
      widget.voice.speak(text, widget.language, enabled: widget.voiceOn);

  /// Records the answer to the current round and moves on.
  void answer(bool correct) {
    if (locked) return;
    engine.recordTrial(correct: correct, responseMs: sw.elapsedMilliseconds);
    setState(() {
      locked = true;
      feedback = correct;
    });
    say(correct ? t('wellDone') : t('tryAgain'));
    after(Duration(milliseconds: correct ? 1100 : 1500), () {
      done++;
      if (done >= rounds) {
        finish();
        return;
      }
      setState(() {
        locked = false;
        feedback = null;
        beginRound();
      });
      sw
        ..reset()
        ..start();
    });
  }

  Future<void> finish() async {
    if (_finishing) return;
    _finishing = true;
    for (final tm in _timers) {
      tm.cancel();
    }
    widget.voice.stop();
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: gameId,
      startedAt: sessionStart,
      startLevel: startLevel,
      engine: engine,
    );
    if (!mounted) return;
    // Left early: nothing to celebrate or measure.
    if (engine.trials >= kMinTrialsForClear) {
      GameProgress? progress;
      try {
        progress = await widget.db
            .gameProgressFor(widget.patientId, gameId, widget.baselineLevel);
      } catch (_) {}
      if (!mounted) return;
      final cleared = engine.accuracy >= kClearAccuracy;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => _ResultDialog(
          lang: widget.language,
          cleared: cleared,
          right: engine.correctTrials,
          of: engine.trials,
          progress: progress,
          playedLevel: startLevel,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final tm in _timers) {
      tm.cancel();
    }
    widget.voice.stop();
    sw.stop();
    super.dispose();
  }

  /// The small banner shown after each answer.
  Widget feedbackBanner() => AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: feedback == null ? 0 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: feedback == false ? Palette.tileOrange : Palette.tileGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            feedback == false ? t('tryAgain') : t('wellDone'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: feedback == false ? Palette.orange : Palette.green),
          ),
        ),
      );

  /// Instruction line + round counter used at the top of every game.
  Widget header(String prompt) => Column(children: [
        Text(prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w600, color: Palette.brandDeep)),
        const SizedBox(height: 4),
        Text(roundText, style: const TextStyle(fontSize: 13, color: Palette.muted)),
        const SizedBox(height: 6),
        SizedBox(height: 36, child: Center(child: feedbackBanner())),
      ]);

  @override
  Widget build(BuildContext context) => GameFrame(
        title: t(titleKey),
        subtitle: t(descKey),
        lang: widget.language,
        score: engine.correctTrials * 10,
        onFinish: finish,
        // On a small screen with large text the play area scrolls instead of
        // squeezing its parts into nothing.
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: SizedBox(
              height: max(c.maxHeight, 560),
              child: buildPlay(context),
            ),
          ),
        ),
      );
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.lang,
    required this.cleared,
    required this.right,
    required this.of,
    required this.progress,
    required this.playedLevel,
  });
  final String lang;
  final bool cleared;
  final int right, of, playedLevel;
  final GameProgress? progress;

  @override
  Widget build(BuildContext context) {
    String t(String k) => tr(lang, k);
    final p = progress;
    final leveledUp = p != null && p.level > playedLevel;
    return AlertDialog(
      backgroundColor: Palette.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cleared ? Palette.tileGreen : Palette.tileOrange),
          child: Icon(cleared ? Icons.emoji_events_rounded : Icons.favorite_rounded,
              size: 46, color: cleared ? Palette.green : Palette.orange),
        ),
        const SizedBox(height: 14),
        Text(cleared ? t('levelCleared') : t('gameFinishedMsg'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: Palette.brandDeep)),
        const SizedBox(height: 6),
        Text('$right / $of',
            style: const TextStyle(fontSize: 18, color: Palette.muted)),
        if (p != null) ...[
          const SizedBox(height: 12),
          if (!leveledUp)
            Text(trf(lang, 'clearsProgress', a: p.clears, b: kClearsToLevelUp),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text(leveledUp ? t('nextHarder') : t('sameLevelNext'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
      ]),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: Text(t('continue'))),
      ],
    );
  }
}

/// A big rounded tile used by several games.
class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.border = Palette.line,
    this.borderWidth = 1.6,
    this.semantics,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color, border;
  final double borderWidth;
  final String? semantics;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semantics,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: border, width: borderWidth),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
}

/// A rows x cols grid of square cells that always fits the space it is given
/// (no scrolling, nothing cut off on a small phone).
class FitGrid extends StatelessWidget {
  const FitGrid({
    super.key,
    required this.rows,
    required this.cols,
    required this.cell,
    this.gap = 10,
    this.maxCell = 120,
  });
  final int rows, cols;
  final Widget Function(int index) cell;
  final double gap, maxCell;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        final h = (c.maxHeight - gap * (rows - 1)) / rows;
        // Never smaller than a comfortable touch target: on a tiny screen with
        // large text the grid scrolls instead of squeezing or overflowing.
        final size = max(56.0, [w, h, maxCell].reduce(min));
        return Center(
          child: SingleChildScrollView(
            child: SizedBox(
            width: size * cols + gap * (cols - 1),
            height: size * rows + gap * (rows - 1),
            child: Column(children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) SizedBox(height: gap),
                Expanded(
                  child: Row(children: [
                    for (var k = 0; k < cols; k++) ...[
                      if (k > 0) SizedBox(width: gap),
                      Expanded(child: cell(r * cols + k)),
                    ],
                  ]),
                ),
              ],
            ]),
            ),
          ),
        );
      });
}

/// Emoji scaled to its cell.
class Emoji extends StatelessWidget {
  const Emoji(this.text, {super.key, this.size = 44});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(text, style: TextStyle(fontSize: size)),
        ),
      );
}

/// A pill with a countdown bar, for the "look now" phases.
class LookBar extends StatelessWidget {
  const LookBar({super.key, required this.seconds});
  final int seconds;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: Duration(seconds: seconds),
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              color: Palette.orange,
              backgroundColor: Palette.tileOrange),
        ),
      );
}
