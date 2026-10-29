import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Common frame for every game: back arrow, title with a one-line subtitle,
/// the playing area, and a footer with Time, Finish and Score as on the design
/// sheet. The back arrow and the phone's back gesture both finish the game so
/// that what was played is saved.
class GameFrame extends StatefulWidget {
  const GameFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.lang,
    required this.onFinish,
    required this.child,
  });
  final String title, subtitle, lang;
  final int score;
  final VoidCallback onFinish;
  final Widget child;

  @override
  State<GameFrame> createState() => _GameFrameState();
}

class _GameFrameState extends State<GameFrame> {
  final _start = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final s = DateTime.now().difference(_start).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => tr(widget.lang, k);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onFinish();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 26),
            onPressed: widget.onFinish,
          ),
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: Palette.brandDeep)),
              Text(widget.subtitle,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Palette.muted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: widget.onFinish,
              child: Text(t('finish'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Palette.brand)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: widget.child),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(child: _stat(t('timeLabel'), _elapsed)),
                        const VerticalDivider(width: 1, color: Palette.line),
                        Expanded(child: _stat(t('scoreLabel'), '${widget.score}')),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Palette.brandDeep)),
        ],
      );
}
