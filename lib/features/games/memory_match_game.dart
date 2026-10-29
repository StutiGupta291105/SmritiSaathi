import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/content.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/voice.dart';
import 'game_common.dart';
import 'game_ui.dart';

class _CardState {
  _CardState(this.pair);
  final int pair;
  bool faceUp = false;
  bool matched = false;
}

/// Pair-matching memory game. Pairs = level + 1 (2..6). Higher level also
/// shortens the initial preview. No failure screens; a miss just flips back.
class MemoryMatchGame extends StatefulWidget {
  const MemoryMatchGame({
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
  final int baselineLevel;

  /// Where this session starts: the learned model's pick inside the band.
  final int startLevel;
  final String language;
  final Voice voice;
  final bool voiceOn;

  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

class _MemoryMatchGameState extends State<MemoryMatchGame> {
  static const int _rounds = 3;

  late final AdaptiveEngine _engine;
  late final int _startLevel;
  final DateTime _sessionStart = DateTime.now();
  final _rng = Random();
  final _sw = Stopwatch();

  List<_CardState> _cards = [];
  List<Item> _roundItems = [];
  int _round = 0;
  int? _first;
  bool _locked = true;
  bool _previewing = true;
  bool _roundDone = false;

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(
        band: DifficultyBand(widget.baselineLevel),
        startLevel: widget.startLevel);
    _startLevel = _engine.level;
    widget.voice
        .speak(_t('memoryPrompt'), widget.language, enabled: widget.voiceOn);
    _startRound();
  }

  String _t(String k) => tr(widget.language, k);

  void _startRound() {
    final pairs = _engine.level + 1;
    final pool = [...kObjects]..shuffle(_rng);
    _roundItems = pool.take(pairs).toList();
    final cards = <_CardState>[
      for (var i = 0; i < pairs; i++) ...[_CardState(i), _CardState(i)],
    ]..shuffle(_rng);
    for (final c in cards) {
      c.faceUp = true; // preview
    }
    setState(() {
      _cards = cards;
      _first = null;
      _locked = true;
      _previewing = true;
      _roundDone = false;
    });
    final previewMs = 5000 - _engine.level * 600; // L1: 4.4s ... L5: 2.0s
    _later(Duration(milliseconds: previewMs), () {
      if (!mounted) return;
      setState(() {
        for (final c in _cards) {
          c.faceUp = false;
        }
        _previewing = false;
        _locked = false;
      });
      _sw
        ..reset()
        ..start();
    });
  }

  void _tap(int i) {
    if (_locked || _previewing) return;
    final card = _cards[i];
    if (card.faceUp || card.matched) return;
    setState(() => card.faceUp = true);

    if (_first == null) {
      _first = i;
      return;
    }

    final first = _first!;
    _first = null;
    _locked = true;
    final responseMs = _sw.elapsedMilliseconds;
    final correct = _cards[first].pair == card.pair;
    _engine.recordTrial(correct: correct, responseMs: responseMs);

    if (correct) {
      _later(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _cards[first].matched = true;
          card.matched = true;
          _locked = false;
        });
        _sw
          ..reset()
          ..start();
        if (_cards.every((c) => c.matched)) _onRoundComplete();
      });
    } else {
      _later(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        setState(() {
          _cards[first].faceUp = false;
          card.faceUp = false;
          _locked = false;
        });
        _sw
          ..reset()
          ..start();
      });
    }
  }

  void _onRoundComplete() {
    setState(() {
      _roundDone = true;
      _locked = true;
    });
    _later(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      _round++;
      if (_round >= _rounds) {
        await _finish();
      } else {
        _startRound();
      }
    });
  }

  Future<void> _finish() async {
    await saveGameSession(
      db: widget.db,
      patientId: widget.patientId,
      game: 'memory_match',
      startedAt: _sessionStart,
      startLevel: _startLevel,
      engine: _engine,
    );
    if (mounted) Navigator.of(context).pop();
  }

  final _timers = <Timer>[];

  void _later(Duration d, void Function() f) => _timers.add(Timer(d, f));

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    widget.voice.stop();
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cards.length <= 4 ? 2 : (_cards.length <= 6 ? 3 : 4);
    return GameFrame(
      title: _t('memoryGame'),
      subtitle: _t('memoryGameDesc'),
      lang: widget.language,
      score: _engine.correctTrials * 10,
      onFinish: _finish,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_roundDone)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_t('wellDone'),
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
            Expanded(
              child: GridView.count(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
                children: [
                  for (var i = 0; i < _cards.length; i++) _buildCard(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(int i) {
    final c = _cards[i];
    final item = _roundItems[c.pair];
    final label = item.label(widget.language);
    final show = c.faceUp || c.matched;
    return Semantics(
      button: true,
      label: show ? label : 'Hidden card',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _tap(i),
        child: Container(
          decoration: BoxDecoration(
            color: c.matched
                ? const Color(0xFFCDEFE2)
                : (show ? const Color(0xFFFBF3E4) : const Color(0xFFA98BE6)),
            border: Border.all(
                color: c.matched
                    ? Palette.action
                    : (show ? const Color(0xFFE8DCC4) : const Color(0xFF9275DA)),
                width: c.matched ? 3 : 1.5),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: show
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.emoji, style: const TextStyle(fontSize: 48)),
                        Text(label,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : const Icon(Icons.eco_rounded, size: 44, color: Color(0x66FFFFFF)),
        ),
      ),
    );
  }
}
