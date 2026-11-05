import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

/// Shown while the encrypted database opens and reminders are set up: logo,
/// name, tagline, a welcome card, loading dots and the motto.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.lang = 'en'});
  final String lang;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  String t(String k) => tr(widget.lang, k);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFECF5ED), Color(0xFFFBF1E4)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Opacity(
                    opacity: ((v - 0.85) / 0.15).clamp(0.0, 1.0),
                    child: Transform.scale(scale: v, child: child),
                  ),
                  child: const BrandLogo(size: 1.35),
                ),
                const SizedBox(height: 4),
                Text(t('tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Palette.brand)),
                const Spacer(flex: 2),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(215),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Palette.line),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text('👴  👵', style: TextStyle(fontSize: 44)),
                      const SizedBox(height: 8),
                      Text(t('namaste'),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Palette.brandDeep)),
                      const SizedBox(height: 4),
                      Text(t('splashBody'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14, color: Palette.muted)),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                _Dots(controller: _dots),
                const SizedBox(height: 10),
                Text(t('loadingCompanion'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Palette.muted)),
                const Spacer(flex: 2),
                Text(t('saathHai'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: Palette.brand)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three green dots that pulse one after another.
class _Dots extends StatelessWidget {
  const _Dots({required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Opacity(
                opacity: _opacity((controller.value - i * 0.18) % 1.0),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                      color: Palette.action, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Bright for the first third of the cycle, dimmer afterwards.
  double _opacity(double phase) => phase < 0.33 ? 1.0 : 0.35;
}
