import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/adaptive_engine.dart';
import '../../core/strings.dart';
import '../../data/app_database.dart';

class _Item {
  const _Item(this.emoji, this.en, this.hi);
  final String emoji, en, hi;
}

// Culturally familiar, widely supported emoji. Later: caregiver-uploaded
// family photos + names (the personalised-content variant for the paper).
const _items = [
  _Item('🥭', 'Mango', 'आम'),
  _Item('🌼', 'Marigold', 'गेंदा'),
  _Item('☕', 'Tea', 'चाय'),
  _Item('🐄', 'Cow', 'गाय'),
  _Item('🥥', 'Coconut', 'नारियल'),
  _Item('🍌', 'Banana', 'केला'),
  _Item('🌺', 'Hibiscus', 'गुड़हल'),
  _Item('🚲', 'Bicycle', 'साइकिल'),
];

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
    required this.language,
  });

  final AppDatabase db;
  final String patientId;
  final int baselineLevel;
  final String language;

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
  List<_Item> _roundItems = [];
  int _round = 0;
  int? _first;
  bool _locked = true;
  bool _previewing = true;
  bool _roundDone = false;

  @override
  void initState() {
    super.initState();
    _engine = AdaptiveEngine(band: DifficultyBand(widget.baselineLevel));
    _startLevel = _engine.level;
    _startRound();
  }

  String _t(String k) => tr(widget.language, k);

  void _startRound() {
    final pairs = _engine.level + 1;
    final pool = [..._items]..shuffle(_rng);
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
    Timer(Duration(milliseconds: previewMs), () {
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
      Timer(const Duration(milliseconds: 600), () {
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
      Timer(const Duration(milliseconds: 1200), () {
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
    Timer(const Duration(milliseconds: 1800), () async {
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
    await widget.db.insertSession(
      patientId: widget.patientId,
      game: 'memory_match',
      startedAt: _sessionStart,
      startLevel: _startLevel,
      endLevel: _engine.level,
      trials: _engine.trials,
      correct: _engine.correctTrials,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _sw.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cards.length <= 4 ? 2 : (_cards.length <= 6 ? 3 : 4);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('memoryGame')),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(_t('finish'), style: const TextStyle(fontSize: 20)),
          ),
        ],
      ),
      body: Padding(
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
    final label = widget.language == 'hi' ? item.hi : item.en;
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
                ? Colors.green.shade100
                : (show ? Colors.white : Colors.teal.shade700),
            border: Border.all(color: Colors.teal.shade900, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: show
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 56)),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                  ],
                )
              : const Icon(Icons.help_outline, size: 56, color: Colors.white),
        ),
      ),
    );
  }
}
