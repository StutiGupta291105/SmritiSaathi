import 'package:flutter/material.dart';

/// Text and layout that follow the screen.
///
/// Fonts in the app are written for a 390 dp wide phone at [kTextBase] = 1. [fontScaleFor] grows
/// them on bigger screens (tablets) and shrinks them a little on very narrow
/// ones, then multiplies by the person's own system font-size setting, so
/// someone who has chosen larger text still gets it. The product is capped so
/// layouts stay usable.
const double kBaseWidth = 390;
const double kMaxContentWidth = 640;

/// The design sheet uses compact type (titles about 20, body about 13). Our
/// sizes were written larger, so everything is brought down by this factor.
/// A person's own system font-size setting is applied on top of it.
const double kTextBase = 0.82;

double fontScaleFor(double width, double systemScale) {
  final screen = (width / kBaseWidth).clamp(0.9, 1.3);
  final system = systemScale.clamp(0.85, 1.6);
  return (kTextBase * screen * system).clamp(0.7, 1.9);
}

/// Wrap the whole app (MaterialApp.builder). On wide screens the content stays
/// in a centred column so lines remain readable instead of stretching.
class ResponsiveScope extends StatelessWidget {
  const ResponsiveScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final scale = fontScaleFor(width, mq.textScaler.scale(1));
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(scale)),
      child: width <= kMaxContentWidth + 80
          ? child
          : ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                  child: ClipRect(child: child),
                ),
              ),
            ),
    );
  }
}
