import 'package:flutter/material.dart';

import '../../core/language_picker.dart';
import '../../core/languages.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../shell/garden.dart';

/// The look of every sign-in screen: the same Sunrise Garden as the Home screen on top
/// (the sky follows the time of day and the plant grows a little with each step), a step
/// timeline under it, then one white card for the form.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.lang,
    required this.title,
    required this.child,
    this.subtitle,
    this.steps = const [],
    this.step = 0,
    this.onBack,
    this.onLangChanged,
    this.banner,
    this.heroHeight = 210,
    this.now,
    this.growth,
  });
  final String lang, title;

  /// How grown the plant is (0 to 1); by default it follows the step.
  final double? growth;
  final String? subtitle;

  /// Labels of the timeline; empty hides it. [step] is the open one (0-based).
  final List<String> steps;
  final int step;
  final VoidCallback? onBack;
  final ValueChanged<String>? onLangChanged;
  final Widget? banner;
  final double heroHeight;
  final Widget child;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final period = periodAt(at);
    final sky = skyFor(period);
    final fg = sky.dark ? Colors.white : Palette.brandDeep;
    final progress =
        growth ?? (steps.isEmpty ? 0.55 : ((step + 1) / steps.length).clamp(0.2, 1.0));
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: heroHeight,
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [sky.top, sky.bottom]),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      key: const ValueKey('authGarden'),
                      painter: GardenPainter(progress: progress, period: period),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: heroHeight < 200 ? 52 : 60,
                    right: 14,
                    child: Row(children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: ClipOval(
                            child: Image.asset('assets/images/logo.png', fit: BoxFit.cover)),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text('Smriti Sathi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: fg,
                                height: 1.1)),
                      ),
                    ]),
                  ),
                  if (onBack != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: IconButton(
                        key: const ValueKey('authBack'),
                        icon: Icon(Icons.arrow_back_rounded, color: fg),
                        onPressed: onBack,
                      ),
                    ),
                  if (onLangChanged != null)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          key: const ValueKey('authLanguage'),
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final picked =
                                await showLanguagePicker(context, current: lang);
                            if (picked != null) onLangChanged!(picked);
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.language_rounded,
                                  size: 18, color: Palette.brandDeep),
                              const SizedBox(width: 6),
                              Text(kLanguages[lang] ?? lang,
                                  style: const TextStyle(
                                      fontSize: 14, color: Palette.brandDeep)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              StepTimeline(steps: steps, current: step),
            ],
            const SizedBox(height: 16),
            if (banner != null) ...[banner!, const SizedBox(height: 12)],
            AppCard(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Palette.brandDeep)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: const TextStyle(fontSize: 14.5, color: Palette.muted)),
                ],
                const SizedBox(height: 16),
                child,
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short line of steps, like the timeline of the day on Home: done steps are ticked, the
/// open one glows, the rest wait.
class StepTimeline extends StatelessWidget {
  const StepTimeline({super.key, required this.steps, required this.current});
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < steps.length; i++) ...[
        Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Container(
                    height: 3,
                    color: i == 0
                        ? Colors.transparent
                        : (i <= current ? Palette.action : Palette.line)),
              ),
              _dot(i),
              Expanded(
                child: Container(
                    height: 3,
                    color: i == steps.length - 1
                        ? Colors.transparent
                        : (i < current ? Palette.action : Palette.line)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(steps[i],
                key: ValueKey('step$i'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                    color: i == current ? Palette.brandDeep : Palette.muted)),
          ]),
        ),
      ],
    ]);
  }

  Widget _dot(int i) {
    if (i < current) {
      return const CircleAvatar(
          radius: 13,
          backgroundColor: Palette.action,
          child: Icon(Icons.check_rounded, size: 17, color: Colors.white));
    }
    if (i == current) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Palette.orange, width: 3),
          boxShadow: [
            BoxShadow(
                color: Palette.orange.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 2),
          ],
        ),
        alignment: Alignment.center,
        child: Text('${i + 1}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: Palette.brandDeep)),
      );
    }
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Palette.line, width: 2)),
      alignment: Alignment.center,
      child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Palette.muted)),
    );
  }
}
