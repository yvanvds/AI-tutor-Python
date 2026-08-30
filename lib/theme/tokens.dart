import 'package:flutter/material.dart';

/// Design tokens for the AI Python Tutor redesign.
///
/// Source: `design_handoff_tutor_redesign/README.md` (Phase 1 — Theme & tokens).
/// Original values are OKLCH; the constants below are the sRGB conversions
/// listed in the README's "approx hex" column. Conversion is done once here
/// and never recomputed at runtime.
class AppColors {
  AppColors._();

  // Base / ink ramp
  static const Color ink0 = Color(0xFF211D18); // canvas, code editor, output
  static const Color ink1 = Color(0xFF28241E); // cards, sidebar, headers
  static const Color ink2 = Color(0xFF332E26); // button bg, hover targets
  static const Color ink3 = Color(0xFF3F3A31); // border, hover, divider strong
  static const Color ink4 = Color(0xFF534D42); // subtle divider

  // Paper (rare — for inverse cards)
  static const Color paper = Color(0xFFF6F1E7);

  // Foreground ramp
  static const Color fg = Color(0xFFEEE9DF); // primary text
  static const Color fgMute = Color(0xFFB1AB9F); // secondary text
  static const Color fgFaint = Color(0xFF7D786D); // tertiary, captions

  // Accent — Blad + zand (default and shipping palette)
  static const Color accent = Color(0xFF7DC89F); // primary accent — leaf
  static const Color accent2 = Color(0xFFDCCF9A); // success / done — sand
  static const Color accent3 = Color(0xFF7AB9D4); // info / hint — blue
  static const Color danger = Color(0xFFD97565); // errors

  // Code syntax — converted from oklch values in the README. These pair
  // with the ink-0 editor background.
  static const Color syntaxKw = Color(
    0xFFE0A4D3,
  ); // keywords — soft pink (oklch(.78 .16 320))
  static const Color syntaxStr = Color(
    0xFF7AD2A4,
  ); // strings — leaf (oklch(.78 .16 150))
  static const Color syntaxNum = Color(
    0xFFDABA6E,
  ); // numbers — amber (oklch(.78 .16 65))
  static const Color syntaxCom = Color(
    0xFF877F71,
  ); // comments — muted (oklch(.55 .014 80))
  static const Color syntaxFn = Color(
    0xFF7EB7DF,
  ); // function calls — blue (oklch(.78 .16 250))
}

/// 4-pt spacing scale used throughout the redesign.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 6;
  static const double s = 8;
  static const double sm = 10;
  static const double m = 12;
  static const double md = 14;
  static const double lg = 16;
  static const double lgPlus = 18;
  static const double xl = 22;
  static const double xxl = 28;
  static const double xxxl = 36;
}

class AppRadius {
  AppRadius._();

  static const double pill = 999;
  static const double inputSmall = 8;
  static const double inputLarge = 10;
  static const double card = 12;
  static const double cardLarge = 14;
  static const double bubble = 14;
  static const double modal = 16;
}

class AppDurations {
  AppDurations._();

  static const Duration modeSwap = Duration(milliseconds: 260);
  static const Duration chatSlide = Duration(milliseconds: 380);
  static const Duration modeFade = Duration(milliseconds: 220);
  static const Duration hover = Duration(milliseconds: 120);
  static const Duration progressFill = Duration(milliseconds: 700);
  static const Duration levelUpPopup = Duration(milliseconds: 320);
}

class AppCurves {
  AppCurves._();

  /// Approximation of `cubic-bezier(.2,.8,.2,1)` used for layout transitions.
  static const Curve layout = Curves.easeOutCubic;

  /// Approximation of `cubic-bezier(.2,.9,.2,1.2)` used for the level-up pop-in.
  static const Curve levelUp = Curves.easeOutBack;
}
