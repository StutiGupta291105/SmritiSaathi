import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../profile/photo_picker.dart' show Avatar;

/// The part of the day, which sets the sky.
enum SkyPeriod { morning, afternoon, evening, night }

SkyPeriod periodAt(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return SkyPeriod.morning;
  if (h >= 11 && h < 17) return SkyPeriod.afternoon;
  if (h >= 17 && h < 20) return SkyPeriod.evening;
  return SkyPeriod.night;
}

({Color top, Color bottom, bool dark}) skyFor(SkyPeriod p) => switch (p) {
      SkyPeriod.morning => (top: const Color(0xFFFFD39B), bottom: const Color(0xFFFFEFD6), dark: false),
      SkyPeriod.afternoon => (top: const Color(0xFFBFE4FF), bottom: const Color(0xFFFBF3EA), dark: false),
      SkyPeriod.evening => (top: const Color(0xFFFFB98A), bottom: const Color(0xFFE9D8F6), dark: false),
      SkyPeriod.night => (top: const Color(0xFF1C2850), bottom: const Color(0xFF3A4C7A), dark: true),
    };

/// A calm garden scene at the top of Home. The sky follows the time of day and
/// the plant grows with the share of today that is done (0 to 1): a sprout, then
/// leaves, then a flower, and a few sparkles when everything is done. There is no
/// score and nothing to fail: an empty day is simply a young plant.
class GardenHeader extends StatelessWidget {
  const GardenHeader({
    super.key,
    required this.greeting,
    required this.name,
    required this.photo,
    required this.progress,
    required this.progressText,
    required this.now,
    this.trailing,
  });
  final String greeting, name, progressText;

  /// Something small in the bottom-right corner (a notification bell, say).
  final Widget? trailing;
  final List<int>? photo;
  final double progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final period = periodAt(now);
    final sky = skyFor(period);
    final fg = sky.dark ? Colors.white : Palette.brandDeep;
    final sub = sky.dark ? const Color(0xFFD5DCF2) : const Color(0xFF55607A);
    return Semantics(
      label: '$greeting $name. $progressText',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 236,
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
                key: const ValueKey('gardenScene'),
                painter: GardenPainter(progress: progress.clamp(0.0, 1.0), period: period),
              ),
            ),
            Positioned(
              left: 18,
              top: 16,
              right: 110,
              child: Row(children: [
                Avatar(photo: photo, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$greeting,', style: TextStyle(fontSize: 14, color: sub)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: fg)),
                  ]),
                ),
              ]),
            ),
            Positioned(
              left: 18,
              bottom: 14,
              child: Container(
                key: const ValueKey('gardenProgress'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(16)),
                child: Text(progressText,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Palette.green)),
              ),
            ),
            if (trailing != null)
              Positioned(right: 12, bottom: 10, child: trailing!),
          ]),
        ),
      ),
    );
  }
}

class GardenPainter extends CustomPainter {
  GardenPainter({required this.progress, required this.period});
  final double progress;
  final SkyPeriod period;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Sun or moon, top right, with a soft glow.
    final night = period == SkyPeriod.night;
    final c = Offset(w - 52, period == SkyPeriod.afternoon ? 40 : 58);
    final glow = Paint()
      ..color = (night ? const Color(0xFFDDE6FF) : const Color(0xFFFFE08A)).withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(c, 40, glow);
    canvas.drawCircle(c, 25, Paint()..color = night ? const Color(0xFFF3F6FF) : const Color(0xFFFFC857));
    if (night) {
      canvas.drawCircle(c.translate(9, -5), 22, Paint()..color = const Color(0xFF2A3A68));
      final star = Paint()..color = Colors.white.withValues(alpha: 0.85);
      for (final p in [const Offset(0.62, 0.12), const Offset(0.78, 0.3), const Offset(0.5, 0.26), const Offset(0.9, 0.5)]) {
        canvas.drawCircle(Offset(w * p.dx, h * p.dy), 1.8, star);
      }
    }
    // Hills.
    final far = Path()
      ..moveTo(0, h * 0.78)
      ..quadraticBezierTo(w * 0.28, h * 0.58, w * 0.6, h * 0.78)
      ..quadraticBezierTo(w * 0.82, h * 0.9, w, h * 0.7)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = night ? const Color(0xFF3F7A66) : const Color(0xFF9AD6A0));
    final near = Path()
      ..moveTo(0, h * 0.9)
      ..quadraticBezierTo(w * 0.35, h * 0.74, w * 0.72, h * 0.9)
      ..quadraticBezierTo(w * 0.9, h * 0.97, w, h * 0.86)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = night ? const Color(0xFF2F6A57) : const Color(0xFF6FC07F));

    // The plant: grows with progress.
    final base = Offset(w * 0.68, h * 0.9);
    final stemH = 26 + 64 * progress;
    final top = base.translate(0, -stemH);
    final stem = Paint()
      ..color = const Color(0xFF2E9A55)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(base, top, stem);
    final leaf = Paint()..color = const Color(0xFF3DB067);
    final leaves = 1 + (progress * 3).floor().clamp(0, 3);
    for (var i = 0; i < leaves; i++) {
      final y = base.dy - stemH * (0.3 + 0.2 * i);
      final dir = i.isEven ? 1.0 : -1.0;
      final size = 13 + 4 * progress;
      final p = Path()
        ..moveTo(base.dx, y)
        ..quadraticBezierTo(base.dx + dir * size * 1.4, y - size * 0.9, base.dx + dir * size * 2, y - size * 0.1)
        ..quadraticBezierTo(base.dx + dir * size, y + size * 0.5, base.dx, y)
        ..close();
      canvas.drawPath(p, leaf);
    }
    // Bud, then flower.
    if (progress < 0.34) {
      canvas.drawCircle(top, 5, Paint()..color = const Color(0xFF3DB067));
    } else {
      final bloom = ((progress - 0.34) / 0.66).clamp(0.0, 1.0);
      final r = 7 + 11 * bloom;
      final petal = Paint()..color = const Color(0xFFFF8FB1);
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        canvas.drawCircle(top + Offset(math.cos(a), math.sin(a)) * r * 0.9, r * 0.62, petal);
      }
      canvas.drawCircle(top, r * 0.55, Paint()..color = const Color(0xFFFFD34D));
    }
    if (progress >= 1) {
      final spark = Paint()..color = Colors.white.withValues(alpha: 0.95);
      for (final o in [const Offset(-34, -22), const Offset(30, -34), const Offset(-12, -52), const Offset(42, -8)]) {
        canvas.drawCircle(top + o, 2.6, spark);
      }
    }
  }

  @override
  bool shouldRepaint(GardenPainter old) => old.progress != progress || old.period != period;
}
