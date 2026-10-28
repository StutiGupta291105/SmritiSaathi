import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// White rounded card with the soft shadow used across the design sheet.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin = EdgeInsets.zero,
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Rounded icon on a pastel square or circle (reminder rows, game rows, tiles).
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.fg,
    required this.bg,
    this.size = 52,
    this.circle = false,
  });
  final IconData icon;
  final Color fg, bg;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(size * 0.28),
        ),
        child: Icon(icon, color: fg, size: size * 0.55),
      );
}

/// The segmented pill row used for Today / Upcoming / All and 7 Days / 30 Days.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Palette.tileGreen.withAlpha(140),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: i == selected ? Palette.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: i == selected ? Colors.white : Palette.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Leaf mark plus wordmark, as on the design sheet.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 1, this.subtitle, this.center = true});
  final double size;
  final String? subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96 * size,
          height: 96 * size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 5)),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
          ),
        ),
        SizedBox(height: 8 * size),
        Text('Smriti Sathi',
            style: TextStyle(
              fontSize: 30 * size,
              fontWeight: FontWeight.w700,
              color: Palette.brandDeep,
              height: 1.1,
            )),
        if (subtitle != null)
          Text(subtitle!,
              style: TextStyle(
                  fontSize: 14 * size,
                  fontWeight: FontWeight.w500,
                  color: Palette.brand)),
      ],
    );
  }
}

/// A simple painted village scene (sky, sun, hills, house, tree) standing in
/// for the illustrated header on the welcome screen.
class SceneHeader extends StatelessWidget {
  const SceneHeader({super.key, this.height = 240});
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _ScenePainter()),
        ),
      );
}

class _ScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBFE3F2), Color(0xFFFBF1D8)],
        ).createShader(Offset.zero & s),
    );
    canvas.drawCircle(
        Offset(w * 0.82, h * 0.22), h * 0.12, Paint()..color = const Color(0xFFFFD86B));

    Path hill(double base, double amp, double phase) {
      final p = Path()..moveTo(0, h);
      p.lineTo(0, h * base);
      for (var x = 0.0; x <= w; x += 4) {
        p.lineTo(x, h * base - amp * h * _wave(x / w * math.pi * 2 + phase));
      }
      p.lineTo(w, h);
      p.close();
      return p;
    }

    canvas.drawPath(hill(0.58, 0.10, 0.5), Paint()..color = const Color(0xFFA9D49A));
    canvas.drawPath(hill(0.68, 0.08, 2.0), Paint()..color = const Color(0xFF6DB57A));

    // House.
    final hx = w * 0.30, hy = h * 0.52, hw = w * 0.22, hh = h * 0.20;
    canvas.drawRect(Rect.fromLTWH(hx, hy, hw, hh), Paint()..color = const Color(0xFFF8E6C6));
    final roof = Path()
      ..moveTo(hx - hw * 0.08, hy)
      ..lineTo(hx + hw / 2, hy - hh * 0.62)
      ..lineTo(hx + hw * 1.08, hy)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFFD9642B));
    canvas.drawRect(
        Rect.fromLTWH(hx + hw * 0.40, hy + hh * 0.35, hw * 0.2, hh * 0.65),
        Paint()..color = const Color(0xFF8A5A3B));

    // Tree.
    final tx = w * 0.72, ty = h * 0.55;
    canvas.drawRect(Rect.fromLTWH(tx - 4, ty, 8, h * 0.16), Paint()..color = const Color(0xFF7A5230));
    canvas.drawCircle(Offset(tx, ty - 6), h * 0.12, Paint()..color = const Color(0xFF2E7D4F));
    canvas.drawCircle(Offset(tx - h * 0.07, ty + 4), h * 0.08, Paint()..color = const Color(0xFF3C9060));

    canvas.drawPath(hill(0.82, 0.05, 4.0), Paint()..color = const Color(0xFF3F8F5A));
  }

  double _wave(double x) => math.sin(x);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Big screen title used at the top of tab pages.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Palette.brandDeep)),
          ),
          if (trailing != null) trailing!,
        ],
      );
}
