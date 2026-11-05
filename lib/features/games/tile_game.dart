import 'package:flutter/material.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Match the Tile: tiles lie face down; turn two at a time and find the
/// matching pairs. Easier levels show the whole board for a moment first.
class TileGame extends RoundGame {
  const TileGame({
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
  State<TileGame> createState() => _TileGameState();
}

class _TileGameState extends RoundGameState<TileGame> {
  @override
  String get gameId => 'tile';
  @override
  String get titleKey => 'gameTile';
  @override
  String get descKey => 'gameTileDesc';
  @override
  int get rounds => 3;

  static const _icons = [
    Icons.local_florist_rounded, Icons.wb_sunny_rounded, Icons.favorite_rounded,
    Icons.star_rounded, Icons.cloud_rounded, Icons.pets_rounded,
    Icons.home_rounded, Icons.music_note_rounded, Icons.directions_bike_rounded,
    Icons.coffee_rounded, Icons.eco_rounded, Icons.cake_rounded,
  ];
  static const _colors = [
    Palette.red, Palette.blue, Palette.green, Palette.orange, Palette.purple, Palette.sky
  ];
  static const _soft = [
    Palette.tileRed, Palette.tileBlue, Palette.tileGreen,
    Palette.tileOrange, Palette.tilePurple, Palette.tileSky
  ];

  List<TileFace> _board = [];
  final Set<int> _matched = {};
  final List<int> _open = [];
  bool _peeking = false;
  int _mistakes = 0;

  @override
  void beginRound() {
    _board = generateTileBoard(level, rng, icons: _icons.length, colors: _colors.length);
    _matched.clear();
    _open.clear();
    _mistakes = 0;
    final peek = tilePeekSeconds(level);
    _peeking = peek > 0;
    if (_peeking) {
      after(Duration(seconds: peek), () => setState(() => _peeking = false));
    }
    say(t('tilePrompt'));
  }

  void _tap(int i) {
    if (locked || _peeking || _matched.contains(i) || _open.contains(i)) return;
    if (_open.length >= 2) return;
    setState(() => _open.add(i));
    if (_open.length < 2) return;
    final a = _board[_open[0]], b = _board[_open[1]];
    if (a.icon == b.icon && a.colorIndex == b.colorIndex) {
      after(const Duration(milliseconds: 350), () {
        setState(() {
          _matched.addAll(_open);
          _open.clear();
        });
        if (_matched.length == _board.length) {
          answer(_mistakes <= tilePairs(level));
        }
      });
    } else {
      _mistakes++;
      after(const Duration(milliseconds: 900), () => setState(_open.clear));
    }
  }

  @override
  Widget buildPlay(BuildContext context) {
    final cols = tileColumns(level);
    final rows = (_board.length / cols).ceil();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        header(t('tilePrompt')),
        Expanded(
          child: FitGrid(
            rows: rows,
            cols: cols,
            gap: 8,
            maxCell: 110,
            cell: (i) {
              final f = _board[i];
              final up = _peeking || _open.contains(i) || _matched.contains(i);
              final done = _matched.contains(i);
              return GameTile(
                semantics: 'tile ${i + 1}',
                color: up ? _soft[f.colorIndex] : Palette.green,
                border: done ? Palette.action : (up ? _colors[f.colorIndex] : Palette.brand),
                borderWidth: done ? 3 : 1.6,
                onTap: () => _tap(i),
                child: up
                    ? FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Icon(_icons[f.icon], size: 44, color: _colors[f.colorIndex]),
                        ),
                      )
                    : const Icon(Icons.spa_rounded, size: 30, color: Colors.white70),
              );
            },
          ),
        ),
      ]),
    );
  }
}
