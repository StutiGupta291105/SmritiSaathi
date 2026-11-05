import 'package:flutter/material.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Sort the Day: put an everyday thing in the right group (food, clothes,
/// animals). From level 4 every other round asks for the morning steps in the
/// order people do them.
class SortGame extends RoundGame {
  const SortGame({
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
  State<SortGame> createState() => _SortGameState();
}

class _SortGameState extends RoundGameState<SortGame> {
  @override
  String get gameId => 'sort';
  @override
  String get titleKey => 'gameSort';
  @override
  String get descKey => 'gameSortDesc';
  @override
  int get rounds => 6;

  static const _catKey = {
    SortCategory.food: 'catFood',
    SortCategory.wear: 'catWear',
    SortCategory.animal: 'catAnimal',
  };
  static const _catIcon = {
    SortCategory.food: Icons.restaurant_rounded,
    SortCategory.wear: Icons.checkroom_rounded,
    SortCategory.animal: Icons.pets_rounded,
  };
  static const _catColor = {
    SortCategory.food: Palette.orange,
    SortCategory.wear: Palette.blue,
    SortCategory.animal: Palette.green,
  };
  static const _catSoft = {
    SortCategory.food: Palette.tileOrange,
    SortCategory.wear: Palette.tileBlue,
    SortCategory.animal: Palette.tileGreen,
  };

  bool _ordering = false;
  late SortRound _sort;
  SortCategory? _picked;
  ({List<String> right, List<String> shuffled})? _order;
  final List<String> _tapped = [];
  int _mistakes = 0;
  String? _wrongFlash;

  @override
  void beginRound() {
    _ordering = level >= 4 && done % 2 == 1;
    _picked = null;
    _tapped.clear();
    _mistakes = 0;
    _wrongFlash = null;
    if (_ordering) {
      _order = generateOrderRound(level, rng);
      say(t('sortOrder'));
    } else {
      _sort = generateSortRound(level, rng);
      say(t('sortAsk'));
    }
  }

  void _tapStep(String step) {
    if (locked || _tapped.contains(step)) return;
    final o = _order!;
    if (step != o.right[_tapped.length]) {
      setState(() {
        _mistakes++;
        _wrongFlash = step;
      });
      after(const Duration(milliseconds: 500), () => setState(() => _wrongFlash = null));
      return;
    }
    setState(() => _tapped.add(step));
    if (_tapped.length == o.right.length) answer(_mistakes == 0);
  }

  @override
  Widget buildPlay(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(children: [
          header(_ordering ? t('sortOrder') : t('sortAsk')),
          Expanded(child: _ordering ? _orderBody() : _sortBody()),
        ]),
      );

  Widget _sortBody() => Column(children: [
        const SizedBox(height: 4),
        SizedBox(
          width: 150,
          height: 150,
          child: GameTile(
              color: Palette.tilePurple,
              border: Palette.purple,
              child: Emoji(_sort.item, size: 80)),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(children: [
            for (final c in _sort.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: 64,
                  child: GameTile(
                    semantics: t(_catKey[c]!),
                    color: _picked == null
                        ? _catSoft[c]!
                        : c == _sort.answer
                            ? Palette.tileGreen
                            : (c == _picked ? Palette.tileOrange : _catSoft[c]!),
                    border: _picked != null && c == _sort.answer
                        ? Palette.action
                        : _catColor[c]!,
                    onTap: locked
                        ? null
                        : () {
                            setState(() => _picked = c);
                            answer(c == _sort.answer);
                          },
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(_catIcon[c], color: _catColor[c], size: 28),
                      const SizedBox(width: 10),
                      Text(t(_catKey[c]!),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Palette.brandDeep)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]);

  Widget _orderBody() {
    final o = _order!;
    return Column(children: [
      // The order so far.
      SizedBox(
        height: 64,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < o.right.length; i++)
            Container(
              width: 52,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: i < _tapped.length ? Palette.tileGreen : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: i < _tapped.length ? Palette.action : Palette.line, width: 2),
              ),
              alignment: Alignment.center,
              child: i < _tapped.length
                  ? Emoji(_tapped[i], size: 28)
                  : Text('${i + 1}',
                      style: const TextStyle(fontSize: 18, color: Palette.muted)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: FitGrid(
          rows: (o.shuffled.length / 3).ceil(),
          cols: 3,
          maxCell: 110,
          cell: (i) {
            if (i >= o.shuffled.length) return const SizedBox();
            final step = o.shuffled[i];
            final used = _tapped.contains(step);
            return GameTile(
              semantics: 'step ${i + 1}',
              color: used
                  ? Palette.line
                  : (_wrongFlash == step ? Palette.tileOrange : Colors.white),
              border: _wrongFlash == step ? Palette.orange : Palette.line,
              onTap: () => _tapStep(step),
              child: Opacity(opacity: used ? 0.35 : 1, child: Emoji(step)),
            );
          },
        ),
      ),
    ]);
  }
}
