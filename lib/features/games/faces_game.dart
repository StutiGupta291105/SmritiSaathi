import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/game_rounds.dart';
import '../../core/theme.dart';
import 'round_game.dart';

/// Who Is This?: look at a few faces with their names, then say whose name
/// goes with a face. Uses the family members saved in the app (with their
/// photos) and fills up with sample faces when there are too few.
class FacesGame extends RoundGame {
  const FacesGame({
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
  State<FacesGame> createState() => _FacesGameState();
}

class _FacesGameState extends RoundGameState<FacesGame> {
  @override
  String get gameId => 'faces';
  @override
  String get titleKey => 'gameFaces';
  @override
  String get descKey => 'gameFacesDesc';

  List<Person>? _family; // null until loaded
  FaceRound? _r;
  bool _studying = true;
  String? _picked;
  Timer? _studyTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var people = <Person>[];
    try {
      final rows = await widget.db.listFamily(widget.patientId);
      people = [
        for (final r in rows)
          Person((r['name'] as String).split(' ').first, '🙂',
              photo: r['photo'] as List<int>?)
      ];
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _family = people;
      beginRound();
    });
  }

  @override
  void beginRound() {
    final fam = _family;
    if (fam == null) return;
    _r = generateFaceRound(level, fam, rng);
    _studying = true;
    _picked = null;
    _studyTimer?.cancel();
    _studyTimer =
        after(Duration(seconds: faceStudySeconds(level)), _endStudy);
    say(t('facesStudy'));
  }

  void _endStudy() {
    if (!_studying) return;
    setState(() => _studying = false);
    sw
      ..reset()
      ..start();
    say(t('facesAsk'));
  }

  @override
  void dispose() {
    _studyTimer?.cancel();
    super.dispose();
  }

  Widget _face(Person p, double size) => ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          color: Palette.tilePurple,
          alignment: Alignment.center,
          child: p.photo != null
              ? Image.memory(Uint8List.fromList(p.photo!),
                  width: size, height: size, fit: BoxFit.cover)
              : Text(p.emoji, style: TextStyle(fontSize: size * 0.55)),
        ),
      );

  @override
  Widget buildPlay(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        header(_studying ? t('facesStudy') : t('facesAsk')),
        Expanded(child: _studying ? _study(r) : _ask(r)),
      ]),
    );
  }

  Widget _study(FaceRound r) => Column(children: [
        LookBar(key: ValueKey('look$done'), seconds: faceStudySeconds(level)),
        const SizedBox(height: 16),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 18,
              runSpacing: 18,
              children: [
                for (final p in r.shown)
                  SizedBox(
                    width: 120,
                    child: Column(children: [
                      _face(p, 104),
                      const SizedBox(height: 6),
                      Text(p.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Palette.brandDeep)),
                    ]),
                  ),
              ],
            ),
            ),
          ),
        ),
        FilledButton(onPressed: _endStudy, child: Text(t('gameReady'))),
      ]);

  Widget _ask(FaceRound r) => Column(children: [
        const SizedBox(height: 4),
        _face(r.asked, 140),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(children: [
            for (final name in r.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: 58,
                  child: GameTile(
                    semantics: name,
                    color: _picked == null
                        ? Colors.white
                        : name == r.asked.name
                            ? Palette.tileGreen
                            : (name == _picked ? Palette.tileOrange : Colors.white),
                    border: _picked != null && name == r.asked.name
                        ? Palette.action
                        : Palette.line,
                    onTap: locked
                        ? null
                        : () {
                            setState(() => _picked = name);
                            answer(name == r.asked.name);
                          },
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Palette.brandDeep)),
                  ),
                ),
              ),
          ]),
        ),
      ]);
}
