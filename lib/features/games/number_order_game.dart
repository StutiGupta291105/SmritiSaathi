import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/number_order_round.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';
import 'game_ui.dart';

/// Number Order: tap the numbers in order. A wrong tap is gently shown and
/// does not stop play; the round only counts as right if there were no wrong
/// taps. Five rounds per session.
class NumberOrderGame extends StatefulWidget {
  const NumberOrderGame({
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
  State<NumberOrderGame> createState() => _NumberOrderGameState();
}

class _NumberOrderGameState extends State<NumberOrderGame> {
  static const _trials = 5;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  late NumberOrderRound _round;
  int _done = 0;
  int _next = 0; // how many of the target have been tapped
  int _mistakes = 0;
  int? _wrongFlash;
  bool _locked = false;
  Timer? _timer;

  String _t(String k) => tr(widget.language, k);
  String get _prompt => _t(_round.ascending ? 'numberAscPrompt' : 'numberDescPrompt');

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(
        band: DifficultyBand(widget.baselineLevel), startLevel: widget.startLevel);
    _startLevel = _engine.level;
    _newRound();
    widget.voice.speak(_prompt, widget.language, enabled: widget.voiceOn);
  }

  void _newRound() {
    _round = generateNumberOrderRound(_engine.level, _rng);
    _next = 0;
    _mistakes = 0;
    _wrongFlash = null;
    _locked = false;
    _sw
      ..reset()
      ..start();
  }

  void _tap(int value) {
    if (_locked || _round.target.take(_next).contains(value)) return;
    if (value != _round.target[_next]) {
      setState(() {
        _mistakes++;
        _wrongFlash = value;
      });
      Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _wrongFlash = null);
      });
      return;
    }
    setState(() => _next++);
    if (_next == _round.numbers.length) {
      _engine.recordTrial(correct: _mistakes == 0, responseMs: _sw.elapsedMilliseconds);
      _locked = true;
      widget.voice.speak(_t('wellDone'), widget.language, enabled: widget.voiceOn);
      _timer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _done++;
        if (_done >= _trials) {
          _finish();
        } else {
          setState(_newRound);
          widget.voice.speak(_prompt, widget.language, enabled: widget.voiceOn);
        }
      });
    }
  }

  Future<void> _finish() async {
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: 'number_order',
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
    final tapped = _round.target.take(_next).toSet();
    return GameFrame(
      title: _t('gameNumberOrder'),
      subtitle: _t('gameNumberOrderDesc'),
      lang: widget.language,
      score: _engine.correctTrials * 10,
      onFinish: _finish,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_prompt,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: Palette.brandDeep)),
            const SizedBox(height: 4),
            Text('${_done + 1} / $_trials',
                style: const TextStyle(fontSize: 14, color: Palette.muted)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: _round.columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final n in _round.numbers) _cell(n, tapped.contains(n)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int n, bool done) {
    final wrong = _wrongFlash == n;
    return Semantics(
      button: true,
      label: '$n',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _tap(n),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: done
                ? Palette.tileGreen
                : (wrong ? Palette.tileOrange : Colors.white),
            border: Border.all(
                color: done
                    ? Palette.action
                    : (wrong ? Palette.orange : Palette.blue),
                width: done || wrong ? 3 : 1.6),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: done ? Palette.green : Palette.brandDeep)),
            ),
          ),
        ),
      ),
    );
  }
}
