import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// `ThemeData` for the redesigned tutor app, built from whatever palette is
/// active in [AppColors].
///
/// The app ships two: the warm "study lamp" dark palette it has always had,
/// and the daylight variant added in #32. Which one is active is decided in
/// `GoalsApp.build` from `appPaletteProvider`; this function only translates
/// the tokens into Material's slots, so both modes get exactly the same
/// component styling.
ThemeData buildAppTheme([AppPalette? palette]) {
  final p = palette ?? AppColors.palette;
  final colorScheme = buildAppColorScheme(p);
  final textTheme = _buildTextTheme(p);

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.ink0,
    canvasColor: p.ink0,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: p.fg, size: 20),
    dividerTheme: DividerThemeData(color: p.ink3, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.ink1,
      foregroundColor: p.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// The token → Material colour-slot mapping, split out of [buildAppTheme] so
/// it can be checked without pulling in the web-fetched text theme.
ColorScheme buildAppColorScheme(AppPalette p) => ColorScheme(
  brightness: p.brightness,
  primary: p.accent,
  onPrimary: p.ink0,
  secondary: p.accent2,
  onSecondary: p.ink0,
  tertiary: p.accent3,
  onTertiary: p.ink0,
  surface: p.ink1,
  onSurface: p.fg,
  surfaceContainerLowest: p.ink0,
  surfaceContainerLow: p.ink1,
  surfaceContainer: p.ink2,
  surfaceContainerHigh: p.ink3,
  surfaceContainerHighest: p.ink4,
  onSurfaceVariant: p.fgMute,
  outline: p.ink3,
  outlineVariant: p.ink2,
  error: p.danger,
  onError: p.isDark ? p.ink0 : p.ink1,
);

TextTheme _buildTextTheme(AppPalette p) {
  // Start from Inter Tight applied to Material's default TextTheme for this
  // brightness so every slot has a sensible base, then override the slots we
  // care about to match the type scale in the README.
  final base = GoogleFonts.interTightTextTheme(
    ThemeData(brightness: p.brightness).textTheme,
  );

  TextStyle s({
    required double size,
    required FontWeight weight,
    required double height,
    double letterSpacing = 0,
    Color? color,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? p.fg,
    );
  }

  return base.copyWith(
    // Hero number (level-up "Level 5")
    displayLarge: GoogleFonts.interTight(
      textStyle: s(
        size: 64,
        weight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -2,
      ),
    ),
    // Page title large (h1, top of scale)
    headlineLarge: GoogleFonts.interTight(
      textStyle: s(
        size: 36,
        weight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.5,
      ),
    ),
    // Page title (h1, default)
    headlineMedium: GoogleFonts.interTight(
      textStyle: s(
        size: 26,
        weight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.3,
      ),
    ),
    // Title (between section and page)
    headlineSmall: GoogleFonts.interTight(
      textStyle: s(size: 20, weight: FontWeight.w600, height: 1.2),
    ),
    titleLarge: GoogleFonts.interTight(
      textStyle: s(size: 18, weight: FontWeight.w600, height: 1.3),
    ),
    // Section title
    titleMedium: GoogleFonts.interTight(
      textStyle: s(size: 16, weight: FontWeight.w600, height: 1.3),
    ),
    // Body emphasis
    titleSmall: GoogleFonts.interTight(
      textStyle: s(size: 14, weight: FontWeight.w600, height: 1.55),
    ),
    // Body large (14.5)
    bodyLarge: GoogleFonts.interTight(
      textStyle: s(size: 14.5, weight: FontWeight.w400, height: 1.55),
    ),
    // Body
    bodyMedium: GoogleFonts.interTight(
      textStyle: s(size: 14, weight: FontWeight.w400, height: 1.55),
    ),
    // Caption
    bodySmall: GoogleFonts.interTight(
      textStyle: s(
        size: 11.5,
        weight: FontWeight.w400,
        height: 1.4,
        color: p.fgMute,
      ),
    ),
    // Button label / large label
    labelLarge: GoogleFonts.interTight(
      textStyle: s(size: 14, weight: FontWeight.w600, height: 1.3),
    ),
    labelMedium: GoogleFonts.interTight(
      textStyle: s(size: 12, weight: FontWeight.w600, height: 1.3),
    ),
    // Pill / uppercase label (apply uppercase at usage site)
    labelSmall: GoogleFonts.interTight(
      textStyle: s(
        size: 11,
        weight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.4,
        color: p.fgFaint,
      ),
    ),
  );
}

/// Mono text styles for code, terminal output, and keyboard glyphs.
/// These don't fit into Material's [TextTheme] cleanly, so they live here.
class AppMono {
  AppMono._();

  /// JetBrains Mono ships programming ligatures on by default (the `calt`
  /// OpenType feature), which fuses `==` / `!=` / `>=` into single glyphs
  /// (═, ≠, ≥) that don't exist in real Python and can't be typed (#83).
  /// Every JetBrains Mono style — here and in `code_theme.dart` — disables
  /// them so students see the literal ASCII characters they must type.
  static const List<FontFeature> noLigatures = [
    FontFeature.disable('calt'),
    FontFeature.disable('liga'),
  ];

  /// Code body — JetBrains Mono 14 / 400 / lh 1.6.
  static TextStyle code({Color? color, double size = 14}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: color ?? AppColors.fg,
      fontFeatures: noLigatures,
    );
  }

  /// Terminal / output text — JetBrains Mono 12.5 / 400 / lh 1.55.
  static TextStyle output({Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      height: 1.55,
      color: color ?? AppColors.fg,
      fontFeatures: noLigatures,
    );
  }

  /// Keyboard glyph — JetBrains Mono 10.5 / 400 / lh 1.4.
  static TextStyle kbd({Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 10.5,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: color ?? AppColors.fgMute,
      fontFeatures: noLigatures,
    );
  }

  /// Tabular-figure number — Inter Tight with `tnum` for streak / XP / counters.
  static TextStyle tnum({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) {
    return GoogleFonts.interTight(
      fontSize: size,
      fontWeight: weight,
      height: 1.2,
      color: color ?? AppColors.fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
