import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/attention_round.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';

/// Attention and concentration: tap the one that is different. Eight trials per
/// session; the first tap decides the trial. A wrong tap is never punished: the
/// right one is shown and play moves on.
class AttentionGame extends StatefulWidget {
  const AttentionGame({
    super.key,
    required this.db,
    required this.patientId,
    required this.baselineLevel,
    required this.language,
    required this.voice,
    required this.voiceOn,
  });
  final AppDatabase db;
  final String patientId;
  final int baselineLevel;
  final String language;
  final Voice voice;
  final bool voiceOn;

  @override
  State<AttentionGame> createState() => _AttentionGameState();
}

class _AttentionGameState extends State<AttentionGame> {
  static const _trials = 8;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  late AttentionRound _round;
  int _done = 0;
  int? _tapped;
  bool _locked = false;
  Timer? _timer;

  String _t(String k) => tr(widget.language, k);

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(band: DifficultyBand(widget.baselineLevel));
    _startLevel = _engine.level;
    widget.voice.speak(_t('attentionPrompt'), widget.language,
        enabled: widget.voiceOn);
    _next();
  }

  void _next() {
    _round = generateAttentionRound(_engine.level, _rng);
    _tapped = null;
    _locked = false;
    _sw
      ..reset()
      ..start();
  }

  void _tap(int i) {
    if (_locked) return;
    final correct = i == _round.targetIndex;
    _engine.recordTrial(correct: correct, responseMs: _sw.elapsedMilliseconds);
    setState(() {
      _tapped = i;
      _locked = true;
    });
    if (correct) {
      widget.voice
          .speak(_t('wellDone'), widget.language, enabled: widget.voiceOn);
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
      game: 'attention',
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('gameAttention')),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(_t('finish'), style: const TextStyle(fontSize: 20)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(_t('attentionPrompt'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${_done + 1} / $_trials', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: _round.columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (var i = 0; i < _round.cells.length; i++) _cell(i),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(int i) {
    final reveal = _locked && i == _round.targetIndex;
    final wrongTap = _tapped == i && i != _round.targetIndex;
    return Semantics(
      button: true,
      label: _round.cells[i].label(widget.language),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _tap(i),
        child: Container(
          decoration: BoxDecoration(
            color: reveal ? Colors.green.shade100 : Colors.white,
            border: Border.all(
              color: reveal
                  ? Colors.green.shade700
                  : (wrongTap ? Colors.orange.shade700 : Palette.brand),
              width: reveal || wrongTap ? 5 : 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_round.cells[i].emoji,
                  style: const TextStyle(fontSize: 56)),
            ),
          ),
        ),
      ),
    );
  }
}
