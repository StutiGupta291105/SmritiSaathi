import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/puzzle_fix_round.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';
import 'game_ui.dart';

/// Puzzle Fix: complete the pattern. One tap decides the round; a wrong tap
/// shows the right piece in place and play moves on. Six rounds per session.
class PuzzleFixGame extends StatefulWidget {
  const PuzzleFixGame({
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

  @override
  State<PuzzleFixGame> createState() => _PuzzleFixGameState();
}

class _PuzzleFixGameState extends State<PuzzleFixGame> {
  static const _trials = 6;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  late PuzzleRound _round;
  int _done = 0;
  int? _tapped;
  bool _locked = false;
  Timer? _timer;

  String _t(String k) => tr(widget.language, k);

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(
        band: DifficultyBand(widget.baselineLevel), startLevel: widget.startLevel);
    _startLevel = _engine.level;
    widget.voice.speak(_t('puzzlePrompt'), widget.language, enabled: widget.voiceOn);
    _next();
  }

  void _next() {
    _round = generatePuzzleRound(_engine.level, _rng);
    _tapped = null;
    _locked = false;
    _sw
      ..reset()
      ..start();
  }

  void _tap(int i) {
    if (_locked) return;
    final correct = i == _round.answerIndex;
    _engine.recordTrial(correct: correct, responseMs: _sw.elapsedMilliseconds);
    setState(() {
      _tapped = i;
      _locked = true;
    });
    if (correct) {
      widget.voice.speak(_t('wellDone'), widget.language, enabled: widget.voiceOn);
    }
    _timer = Timer(Duration(milliseconds: correct ? 1000 : 1800), () {
      if (!mounted) return;
      _done++;
      if (_done >= _trials) {
        _finish();
      } else {
        setState(_next);
      }
    });
  }

  Future<void> _finish() async {
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: 'puzzle_fix',
      startedAt: _sessionStart,
      startLevel: _startLevel,
      engine: _engine,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.voice.stop();
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GameFrame(
      title: _t('gamePuzzleFix'),
      subtitle: _t('gamePuzzleFixDesc'),
      lang: widget.language,
      score: _engine.correctTrials * 10,
      onFinish: _finish,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_t('puzzlePrompt'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: Palette.brandDeep)),
            const SizedBox(height: 4),
            Text('${_done + 1} / $_trials',
                style: const TextStyle(fontSize: 14, color: Palette.muted)),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1.0 * _round.sequence.length / 1.6,
              child: Row(
                children: [
                  for (var i = 0; i < _round.sequence.length; i++)
                    Expanded(child: _slot(i)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: _round.options.length == 4 ? 2 : 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (var i = 0; i < _round.options.length; i++) _option(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(int i) {
    final missing = i == _round.missingAt;
    final filled = !missing || _locked;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        decoration: BoxDecoration(
          color: missing
              ? (_locked
                  ? (_tapped == _round.answerIndex
                      ? Palette.tileGreen
                      : Palette.tileOrange)
                  : Palette.tilePurple)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: missing ? Palette.purple : Palette.line,
              width: missing ? 2.4 : 1.2),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: filled
                ? Text(_round.sequence[i].emoji, style: const TextStyle(fontSize: 34))
                : const Text('?',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Palette.purple)),
          ),
        ),
      ),
    );
  }

  Widget _option(int i) {
    final reveal = _locked && i == _round.answerIndex;
    final wrongTap = _tapped == i && i != _round.answerIndex;
    return Semantics(
      button: true,
      label: _round.options[i].label(widget.language),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _tap(i),
        child: Container(
          decoration: BoxDecoration(
            color: reveal ? Palette.tileGreen : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: reveal
                  ? Palette.action
                  : (wrongTap ? Palette.orange : Palette.blue),
              width: reveal || wrongTap ? 4 : 1.6,
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_round.options[i].emoji,
                  style: const TextStyle(fontSize: 48)),
            ),
          ),
        ),
      ),
    );
  }
}
