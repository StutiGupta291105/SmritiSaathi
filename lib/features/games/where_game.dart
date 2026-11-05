import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Where Did It Go?: a few pictures sit in a grid for a moment, then are
/// hidden. Tap the square where a named picture was.
class WhereGame extends RoundGame {
  const WhereGame({
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
  State<WhereGame> createState() => _WhereGameState();
}

class _WhereGameState extends RoundGameState<WhereGame> {
  @override
  String get gameId => 'where';
  @override
  String get titleKey => 'gameWhere';
  @override
  String get descKey => 'gameWhereDesc';

  late WhereRound _r;
  bool _studying = true;
  int? _picked;
  Timer? _studyTimer;

  @override
  void beginRound() {
    _r = generateWhereRound(level, rng);
    _studying = true;
    _picked = null;
    _studyTimer?.cancel();
    _studyTimer = after(Duration(seconds: whereStudySeconds(level)), _endStudy);
    say(t('whereStudy'));
  }

  void _endStudy() {
    if (!_studying) return;
    setState(() => _studying = false);
    sw
      ..reset()
      ..start();
    say(t('whereAsk'));
  }

  @override
  void dispose() {
    _studyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildPlay(BuildContext context) {
    final reveal = _studying || feedback != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        header(_studying ? t('whereStudy') : t('whereAsk')),
        if (_studying)
          LookBar(key: ValueKey('look$done'), seconds: whereStudySeconds(level))
        else
          SizedBox(
              height: 84,
              child: Center(
                  child: SizedBox(
                      width: 84,
                      child: GameTile(
                          color: Palette.tileOrange,
                          border: Palette.orange,
                          child: Emoji(_r.placed[_r.asked]!, size: 48))))),
        const SizedBox(height: 12),
        Expanded(
          child: FitGrid(
            rows: _r.rows,
            cols: _r.cols,
            cell: (i) {
              final obj = _r.placed[i];
              final isRight = i == _r.asked;
              Color color = Colors.white, border = Palette.line;
              if (!_studying && _picked != null) {
                if (isRight) {
                  color = Palette.tileGreen;
                  border = Palette.action;
                } else if (i == _picked) {
                  color = Palette.tileOrange;
                  border = Palette.orange;
                }
              }
              return GameTile(
                semantics: 'cell ${i + 1}',
                color: reveal ? (obj != null ? Palette.tileBlue : Colors.white) : color,
                border: border,
                onTap: _studying || locked
                    ? null
                    : () {
                        setState(() => _picked = i);
                        answer(i == _r.asked);
                      },
                child: reveal && obj != null
                    ? Emoji(obj)
                    : const Icon(Icons.help_outline_rounded,
                        size: 32, color: Palette.muted),
              );
            },
          ),
        ),
        if (_studying)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(onPressed: _endStudy, child: Text(t('gameReady'))),
          ),
      ]),
    );
  }
}
