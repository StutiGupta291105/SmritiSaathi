import 'package:flutter/material.dart';

/// Visual system taken from the design mockups: deep green brand colour on a
/// warm cream background, soft pastel tiles, rounded cards, very large targets.
class Palette {
  static const brand = Color(0xFF1F6F5B);
  static const cream = Color(0xFFFBF6EC);
  static const tileBlue = Color(0xFFDCEBFA);
  static const tileOrange = Color(0xFFFDE7CF);
  static const tileGreen = Color(0xFFDDF1E4);
  static const tilePurple = Color(0xFFE9E1F8);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.brand,
    primary: Palette.brand,
    surface: Palette.cream,
  );
  const radius = BorderRadius.all(Radius.circular(20));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.cream,
    // Elderly-friendly: large text; the OS text-size setting still applies.
    textTheme: Typography.blackMountainView.apply(fontSizeFactor: 1.2),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.cream,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 80,
      backgroundColor: Colors.white,
    ),
  );
}
