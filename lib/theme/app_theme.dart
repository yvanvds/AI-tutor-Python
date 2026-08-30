import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Single dark `ThemeData` for the redesigned tutor app.
///
/// There is no light mode — the design is always the warm "study lamp"
/// palette defined in [AppColors].
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.ink0,
    secondary: AppColors.accent2,
    onSecondary: AppColors.ink0,
    tertiary: AppColors.accent3,
    onTertiary: AppColors.ink0,
    surface: AppColors.ink1,
    onSurface: AppColors.fg,
    surfaceContainerLowest: AppColors.ink0,
    surfaceContainerLow: AppColors.ink1,
    surfaceContainer: AppColors.ink2,
    surfaceContainerHigh: AppColors.ink3,
    surfaceContainerHighest: AppColors.ink4,
    onSurfaceVariant: AppColors.fgMute,
    outline: AppColors.ink3,
    outlineVariant: AppColors.ink2,
    error: AppColors.danger,
    onError: AppColors.ink0,
  );

  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.ink0,
    canvasColor: AppColors.ink0,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: const IconThemeData(color: AppColors.fg, size: 20),
    dividerTheme: const DividerThemeData(
      color: AppColors.ink3,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ink1,
      foregroundColor: AppColors.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

TextTheme _buildTextTheme() {
  // Start from Inter Tight applied to Material's default dark TextTheme so
  // every slot has a sensible base, then override the slots we care about
  // to match the type scale in the README.
  final base = GoogleFonts.interTightTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );

  TextStyle s({
    required double size,
    required FontWeight weight,
    required double height,
    double letterSpacing = 0,
    Color color = AppColors.fg,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
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
        color: AppColors.fgMute,
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
        color: AppColors.fgFaint,
      ),
    ),
  );
}

/// Mono text styles for code, terminal output, and keyboard glyphs.
/// These don't fit into Material's [TextTheme] cleanly, so they live here.
class AppMono {
  AppMono._();

  /// Code body — JetBrains Mono 14 / 400 / lh 1.6.
  static TextStyle code({Color color = AppColors.fg, double size = 14}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: color,
    );
  }

  /// Terminal / output text — JetBrains Mono 12.5 / 400 / lh 1.55.
  static TextStyle output({Color color = AppColors.fg}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      height: 1.55,
      color: color,
    );
  }

  /// Keyboard glyph — JetBrains Mono 10.5 / 400 / lh 1.4.
  static TextStyle kbd({Color color = AppColors.fgMute}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 10.5,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: color,
    );
  }

  /// Tabular-figure number — Inter Tight with `tnum` for streak / XP / counters.
  static TextStyle tnum({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.fg,
  }) {
    return GoogleFonts.interTight(
      fontSize: size,
      fontWeight: weight,
      height: 1.2,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
