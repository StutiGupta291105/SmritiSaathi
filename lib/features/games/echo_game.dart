import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Sequence Echo: tiles light up one after another; tap them back in the same
/// order. The sequence is longer at higher levels.
class EchoGame extends RoundGame {
  const EchoGame({
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
  State<EchoGame> createState() => _EchoGameState();
}

class _EchoGameState extends RoundGameState<EchoGame> {
  @override
  String get gameId => 'echo';
  @override
  String get titleKey => 'gameEcho';
  @override
  String get descKey => 'gameEchoDesc';

  static const _colors = [
    Palette.red, Palette.blue, Palette.green, Palette.orange, Palette.purple, Palette.sky
  ];
  static const _soft = [
    Palette.tileRed, Palette.tileBlue, Palette.tileGreen,
    Palette.tileOrange, Palette.tilePurple, Palette.tileSky
  ];

  List<int> _seq = [];
  int _lit = -1; // tile that is lit right now
  bool _watching = true;
  int _at = 0; // how many the player has tapped right

  @override
  void beginRound() {
    _seq = generateEchoSequence(level, rng);
    _watching = true;
    _lit = -1;
    _at = 0;
    say(t('echoWatch'));
    var ms = 900;
    for (final tile in _seq) {
      after(Duration(milliseconds: ms), () => setState(() => _lit = tile));
      after(Duration(milliseconds: ms + 520), () => setState(() => _lit = -1));
      ms += 820;
    }
    after(Duration(milliseconds: ms), () {
      setState(() => _watching = false);
      sw
        ..reset()
        ..start();
      say(t('echoRepeat'));
    });
  }

  void _tap(int tile) {
    if (_watching || locked) return;
    HapticFeedback.selectionClick();
    setState(() => _lit = tile);
    after(const Duration(milliseconds: 220), () => setState(() => _lit = -1));
    if (tile != _seq[_at]) {
      answer(false);
      return;
    }
    _at++;
    if (_at == _seq.length) answer(true);
  }

  @override
  Widget buildPlay(BuildContext context) {
    final n = echoTiles(level);
    final cols = n == 4 ? 2 : 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        header(_watching ? t('echoWatch') : t('echoRepeat')),
        // Progress dots: how many are left to tap.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _seq.length; i++)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _at ? Palette.green : Palette.line,
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: FitGrid(
            rows: n ~/ cols,
            cols: cols,
            maxCell: 150,
            cell: (i) => GameTile(
              semantics: 'tile ${i + 1}',
              color: _lit == i ? _colors[i] : _soft[i],
              border: _colors[i],
              borderWidth: _lit == i ? 4 : 2,
              onTap: () => _tap(i),
              child: Icon(Icons.eco_rounded,
                  size: 44, color: _lit == i ? Colors.white : _colors[i]),
            ),
          ),
        ),
      ]),
    );
  }
}
