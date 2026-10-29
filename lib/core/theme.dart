import 'package:flutter/material.dart';

/// Colours taken from the design sheet: teal-green brand on a warm cream
/// background, bright green action buttons, soft pastel tiles with a stronger
/// icon colour of the same hue.
class Palette {
  static const brand = Color(0xFF1B7F63); // nav highlight, links, accents
  static const brandDeep = Color(0xFF0F2A47); // headings and wordmark: deep navy, as on the sheet
  static const action = Color(0xFF2FA864); // primary buttons ("Play Now")
  static const cream = Color(0xFFFBF7EE);
  static const ink = Color(0xFF1F2A37);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE7E2D6);

  // Pastel tile backgrounds (kept under their original names).
  static const tileBlue = Color(0xFFDDE8FB);
  static const tileOrange = Color(0xFFFDE8D0);
  static const tileGreen = Color(0xFFD9F1E3);
  static const tilePurple = Color(0xFFE9E1F8);
  static const tileSky = Color(0xFFD8EEF7);
  static const tileRed = Color(0xFFFDE3E1);

  // Matching strong colours for icons.
  static const blue = Color(0xFF3B6FE0);
  static const orange = Color(0xFFF08A24);
  static const green = Color(0xFF1B7F63);
  static const purple = Color(0xFF8B6CE0);
  static const sky = Color(0xFF2A9DC8);
  static const red = Color(0xFFE5484D);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.brand,
    primary: Palette.brand,
    surface: Palette.cream,
    onSurface: Palette.ink,
  );
  const radius = BorderRadius.all(Radius.circular(20));
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: Palette.cream,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.cream,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.brandDeep,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Palette.brandDeep),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.action,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.brand,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Palette.line, width: 1.2),
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
        textStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.brand, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x22000000),
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? Palette.brand
                : Palette.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected)
                ? Palette.brand
                : Palette.muted,
          )),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: Palette.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
  return base;
}
