import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Spot the Change: look at a garden picture, then see it again with one
/// thing changed. Tap what is different.
class ChangeGame extends RoundGame {
  const ChangeGame({
    super.key,
    required super.db,
    required super.patientId,
    required super.baselineLevel,
    required super.startLevel,
    required super.language,
    required super.voice,
    required super.voiceOn,
  });

  @override
  State<ChangeGame> createState() => _ChangeGameState();
}

class _ChangeGameState extends RoundGameState<ChangeGame> {
  @override
  String get gameId => 'change';
  @override
  String get titleKey => 'gameChange';
  @override
  String get descKey => 'gameChangeDesc';

  late ChangeRound _r;
  int _phase = 0; // 0 look, 1 blink, 2 find
  int? _picked;
  Timer? _studyTimer;

  @override
  void beginRound() {
    _r = generateChangeRound(level, rng);
    _phase = 0;
    _picked = null;
    _studyTimer?.cancel();
    _studyTimer = after(Duration(seconds: changeStudySeconds(level)), _endStudy);
    say(t('changeStudy'));
  }

  void _endStudy() {
    if (_phase != 0) return;
    setState(() => _phase = 1);
    after(const Duration(milliseconds: 900), () {
      setState(() => _phase = 2);
      sw
        ..reset()
        ..start();
      say(t('changeAsk'));
    });
  }

  @override
  void dispose() {
    _studyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildPlay(BuildContext context) {
    final cols = changeColumns(level);
    final items = _phase == 2 ? _r.after : _r.before;
    final rows = (items.length / cols).ceil();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        header(_phase == 2 ? t('changeAsk') : t('changeStudy')),
        if (_phase == 0)
          LookBar(key: ValueKey('look$done'), seconds: changeStudySeconds(level))
        else
          const SizedBox(height: 8),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Palette.tileGreen,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Palette.line),
            ),
            child: _phase == 1
                ? const Center(
                    child: Icon(Icons.wb_sunny_rounded, size: 56, color: Palette.orange))
                : FitGrid(
                    rows: rows,
                    cols: cols,
                    gap: 8,
                    cell: (i) {
                      if (i >= items.length) return const SizedBox();
                      final right = i == _r.changed;
                      final picked = _picked == i;
                      return GameTile(
                        semantics: 'item ${i + 1}',
                        color: _picked != null && right
                            ? Palette.tileGreen
                            : (picked ? Palette.tileOrange : Colors.white),
                        border: _picked != null && right
                            ? Palette.action
                            : (picked ? Palette.orange : Palette.line),
                        onTap: _phase != 2 || locked
                            ? null
                            : () {
                                setState(() => _picked = i);
                                answer(right);
                              },
                        child: Emoji(items[i]),
                      );
                    },
                  ),
          ),
        ),
        if (_phase == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(onPressed: _endStudy, child: Text(t('gameReady'))),
          ),
      ]),
    );
  }
}
