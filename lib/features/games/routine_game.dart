import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/content.dart';
import '../../core/routine_round.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';

/// Daily-routine recall: tap the steps in the order they usually happen. Each
/// tap is one trial (right next step or not). A wrong tap only shakes the card
/// and the person tries again; nothing is lost and there is no fail screen.
class RoutineGame extends StatefulWidget {
  const RoutineGame({
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
  State<RoutineGame> createState() => _RoutineGameState();
}

class _RoutineGameState extends State<RoutineGame> {
  static const _rounds = 3;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  late RoutineRound _round;
  int _roundNo = 0;
  int _placed = 0; // how many steps are correctly placed so far
  int? _wrong; // index (in shuffled) of the last wrong tap
  bool _roundDone = false;
  Timer? _timer;

  String _t(String k) => tr(widget.language, k);

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(band: DifficultyBand(widget.baselineLevel));
    _startLevel = _engine.level;
    widget.voice.speak(_t('routinePrompt'), widget.language,
        enabled: widget.voiceOn);
    _newRound();
  }

  void _newRound() {
    _round = generateRoutineRound(_engine.level, _rng);
    _placed = 0;
    _wrong = null;
    _roundDone = false;
    _sw
      ..reset()
      ..start();
  }

  void _tap(int i) {
    if (_roundDone) return;
    final item = _round.shuffled[i];
    if (_isPlaced(item)) return;
    final correct = item.en == _round.ordered[_placed].en;
    _engine.recordTrial(correct: correct, responseMs: _sw.elapsedMilliseconds);
    _sw
      ..reset()
      ..start();
    if (!correct) {
      setState(() => _wrong = i);
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _wrong = null);
      });
      return;
    }
    setState(() {
      _wrong = null;
      _placed++;
      _roundDone = _placed == _round.ordered.length;
    });
    widget.voice.speak(item.label(widget.language), widget.language,
        enabled: widget.voiceOn);
    if (_roundDone) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        _roundNo++;
        if (_roundNo >= _rounds) {
          _finish();
        } else {
          setState(_newRound);
        }
      });
    }
  }

  bool _isPlaced(Item item) {
    for (var k = 0; k < _placed; k++) {
      if (_round.ordered[k].en == item.en) return true;
    }
    return false;
  }

  Future<void> _finish() async {
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: 'routine',
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
    final lang = widget.language;
    final title = lang == 'hi' ? _round.routine.hi : _round.routine.en;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('gameRoutine')),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(_t('finish'), style: const TextStyle(fontSize: 20)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('$title: ${_t('routinePrompt')}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            // Steps placed so far, in order, numbered.
            for (var k = 0; k < _placed; k++)
              Card(
                color: Palette.tileGreen,
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Palette.brand,
                      foregroundColor: Colors.white,
                      child: Text('${k + 1}')),
                  title: Text(
                      '${_round.ordered[k].emoji}  ${_round.ordered[k].label(lang)}',
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
            if (_roundDone)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_t('wellDone'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
              )
            else ...[
              const Divider(height: 24),
              for (var i = 0; i < _round.shuffled.length; i++)
                if (!_isPlaced(_round.shuffled[i]))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _tap(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          decoration: BoxDecoration(
                            color: _wrong == i
                                ? Colors.orange.shade100
                                : Colors.white,
                            border: Border.all(
                                color: _wrong == i
                                    ? Colors.orange.shade700
                                    : Palette.brand,
                                width: _wrong == i ? 4 : 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Text(_round.shuffled[i].emoji,
                                  style: const TextStyle(fontSize: 40)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(_round.shuffled[i].label(lang),
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
