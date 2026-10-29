import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/word_recall_round.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';
import 'game_ui.dart';

/// Word Recall: a few pictures with their words are shown for a few seconds,
/// then hidden; the person picks the ones they saw. A wrong set is never
/// scolded: the right ones are shown and play moves on. Four rounds per session.
class WordRecallGame extends StatefulWidget {
  const WordRecallGame({
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
  State<WordRecallGame> createState() => _WordRecallGameState();
}

enum _Phase { memorize, pick, reveal }

class _WordRecallGameState extends State<WordRecallGame> {
  static const _trials = 4;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  late WordRecallRound _round;
  _Phase _phase = _Phase.memorize;
  int _left = 0;
  int _done = 0;
  final _picked = <int>{};
  Timer? _tick;
  Timer? _after;

  String _t(String k) => tr(widget.language, k);

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(
        band: DifficultyBand(widget.baselineLevel), startLevel: widget.startLevel);
    _startLevel = _engine.level;
    _newRound();
  }

  void _newRound() {
    _round = generateWordRecallRound(_engine.level, _rng);
    _picked.clear();
    _phase = _Phase.memorize;
    _left = _round.seconds;
    widget.voice.speak(
        _round.shown.map((i) => i.label(widget.language)).join(', '),
        widget.language,
        enabled: widget.voiceOn);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        setState(() {
          _phase = _Phase.pick;
          _sw
            ..reset()
            ..start();
        });
      }
    });
  }

  void _toggle(int i) {
    if (_phase != _Phase.pick) return;
    setState(() {
      if (!_picked.remove(i)) _picked.add(i);
    });
    if (_picked.length == _round.shown.length) _check();
  }

  void _check() {
    final correct = _picked.length == _round.answerIndexes.length &&
        _picked.containsAll(_round.answerIndexes);
    _engine.recordTrial(correct: correct, responseMs: _sw.elapsedMilliseconds);
    setState(() => _phase = _Phase.reveal);
    if (correct) {
      widget.voice.speak(_t('wellDone'), widget.language, enabled: widget.voiceOn);
    }
    _after = Timer(Duration(milliseconds: correct ? 1200 : 2200), () {
      if (!mounted) return;
      _done++;
      if (_done >= _trials) {
        _finish();
      } else {
        setState(_newRound);
      }
    });
  }

  Future<void> _finish() async {
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: 'word_recall',
      startedAt: _sessionStart,
      startLevel: _startLevel,
      engine: _engine,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _after?.cancel();
    widget.voice.stop();
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memorize = _phase == _Phase.memorize;
    return GameFrame(
      title: _t('gameWordRecall'),
      subtitle: _t('gameWordRecallDesc'),
      lang: widget.language,
      score: _engine.correctTrials * 10,
      onFinish: _finish,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_t(memorize ? 'wordRecallPrompt' : 'wordRecallPick'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: Palette.brandDeep)),
            const SizedBox(height: 4),
            Text(
                memorize
                    ? trf(widget.language, 'secondsLeft', a: _left.clamp(0, 99))
                    : '${_done + 1} / $_trials',
                style: const TextStyle(fontSize: 14, color: Palette.muted)),
            const SizedBox(height: 14),
            Expanded(child: memorize ? _memorize() : _options()),
          ],
        ),
      ),
    );
  }

  Widget _memorize() => Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final i in _round.shown)
              Container(
                width: 120,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Palette.line),
                ),
                child: Column(children: [
                  Text(i.emoji, style: const TextStyle(fontSize: 46)),
                  const SizedBox(height: 4),
                  Text(i.label(widget.language),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      );

  Widget _options() {
    final reveal = _phase == _Phase.reveal;
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (var i = 0; i < _round.options.length; i++) _option(i, reveal),
      ],
    );
  }

  Widget _option(int i, bool reveal) {
    final item = _round.options[i];
    final isAnswer = _round.answerIndexes.contains(i);
    final picked = _picked.contains(i);
    Color border = Palette.line;
    Color fill = Colors.white;
    if (reveal) {
      if (isAnswer) {
        border = Palette.action;
        fill = Palette.tileGreen;
      } else if (picked) {
        border = Palette.orange;
        fill = Palette.tileOrange;
      }
    } else if (picked) {
      border = Palette.purple;
      fill = Palette.tilePurple;
    }
    return Semantics(
      button: true,
      selected: picked,
      label: item.label(widget.language),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggle(i),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: picked || (reveal && isAnswer) ? 3 : 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 38)),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(item.label(widget.language),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
