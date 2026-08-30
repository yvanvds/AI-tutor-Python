import 'package:flutter/material.dart';

/// Design tokens for the AI Python Tutor redesign.
///
/// Source: `design_handoff_tutor_redesign/README.md` (Phase 1 — Theme &
/// tokens). The dark values are the sRGB conversions of the README's OKLCH
/// column; the light set (#32) is the same ramp inverted — paper instead of
/// ink, with the accents and syntax hues darkened until they carry on a warm
/// off-white ground.
///
/// One palette is active at a time; [AppColors] reads it. See
/// `services/config/theme_service.dart` for who sets it and why swapping it
/// remounts the shell.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.ink0,
    required this.ink1,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.paper,
    required this.fg,
    required this.fgMute,
    required this.fgFaint,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.danger,
    required this.syntaxKw,
    required this.syntaxStr,
    required this.syntaxNum,
    required this.syntaxCom,
    required this.syntaxFn,
  });

  final Brightness brightness;

  // Base / ink ramp — darkest-to-lightest in dark mode, lightest-to-darkest
  // in light mode. `ink0` is always the canvas and `ink4` always the most
  // contrasting divider, so usage sites never have to know which is which.
  final Color ink0; // canvas, code editor, output
  final Color ink1; // cards, sidebar, headers
  final Color ink2; // button bg, hover targets
  final Color ink3; // border, hover, divider strong
  final Color ink4; // subtle divider

  /// The inverse of the canvas — for the rare card that flips the contrast.
  final Color paper;

  // Foreground ramp
  final Color fg; // primary text
  final Color fgMute; // secondary text
  final Color fgFaint; // tertiary, captions

  // Accent — Blad + zand
  final Color accent; // primary accent — leaf
  final Color accent2; // success / done — sand
  final Color accent3; // info / hint — blue
  final Color danger; // errors

  // Code syntax — paired with the `ink0` editor background.
  final Color syntaxKw; // keywords
  final Color syntaxStr; // strings
  final Color syntaxNum; // numbers
  final Color syntaxCom; // comments
  final Color syntaxFn; // function calls

  bool get isDark => brightness == Brightness.dark;

  /// The shipping "study lamp" palette.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    ink0: Color(0xFF211D18),
    ink1: Color(0xFF28241E),
    ink2: Color(0xFF332E26),
    ink3: Color(0xFF3F3A31),
    ink4: Color(0xFF534D42),
    paper: Color(0xFFF6F1E7),
    fg: Color(0xFFEEE9DF),
    fgMute: Color(0xFFB1AB9F),
    fgFaint: Color(0xFF7D786D),
    accent: Color(0xFF7DC89F),
    accent2: Color(0xFFDCCF9A),
    accent3: Color(0xFF7AB9D4),
    danger: Color(0xFFD97565),
    syntaxKw: Color(0xFFE0A4D3), // soft pink   oklch(.78 .16 320)
    syntaxStr: Color(0xFF7AD2A4), // leaf        oklch(.78 .16 150)
    syntaxNum: Color(0xFFDABA6E), // amber       oklch(.78 .16 65)
    syntaxCom: Color(0xFF877F71), // muted       oklch(.55 .014 80)
    syntaxFn: Color(0xFF7EB7DF), // blue        oklch(.78 .16 250)
  );

  /// Daylight variant (#32). Same hues, same roles, inverted lightness: the
  /// warm paper that was `AppPalette.dark.paper` becomes the canvas, cards
  /// lift *above* it rather than below, and every accent drops to roughly
  /// oklch L .5 so it stays legible on that ground.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    ink0: Color(0xFFF6F1E7),
    ink1: Color(0xFFFFFCF5),
    ink2: Color(0xFFEBE4D5),
    ink3: Color(0xFFD9D0BD),
    ink4: Color(0xFFC0B5A0),
    paper: Color(0xFF211D18),
    fg: Color(0xFF241F19),
    fgMute: Color(0xFF5B5449),
    fgFaint: Color(0xFF817A6C),
    accent: Color(0xFF2C7A55),
    accent2: Color(0xFF8A6A18),
    accent3: Color(0xFF1B6484),
    danger: Color(0xFFB03A28),
    syntaxKw: Color(0xFF8E2478),
    syntaxStr: Color(0xFF1B6E45),
    syntaxNum: Color(0xFF8A5300),
    syntaxCom: Color(0xFF7A7263),
    syntaxFn: Color(0xFF1A5686),
  );
}

/// The active palette, as flat names so the 380-odd usage sites read the same
/// as they did when there was only one theme.
///
/// These are getters, not `const`s: the palette is swapped when the user
/// changes the theme (see `ThemeService`). That is deliberate — a `const`
/// would let a colour be baked into a `const` widget and survive the swap,
/// and the compiler now refuses every such site instead.
class AppColors {
  AppColors._();

  static AppPalette _active = AppPalette.dark;

  /// The palette every getter below reads.
  static AppPalette get palette => _active;

  /// Swaps the active palette. Called from `GoalsApp.build` before the
  /// `ThemeData` for that brightness is built; the shell below it is remounted
  /// on the same frame so nothing keeps a stale colour.
  static void use(AppPalette palette) => _active = palette;

  static Color get ink0 => _active.ink0;
  static Color get ink1 => _active.ink1;
  static Color get ink2 => _active.ink2;
  static Color get ink3 => _active.ink3;
  static Color get ink4 => _active.ink4;

  static Color get paper => _active.paper;

  static Color get fg => _active.fg;
  static Color get fgMute => _active.fgMute;
  static Color get fgFaint => _active.fgFaint;

  static Color get accent => _active.accent;
  static Color get accent2 => _active.accent2;
  static Color get accent3 => _active.accent3;
  static Color get danger => _active.danger;

  static Color get syntaxKw => _active.syntaxKw;
  static Color get syntaxStr => _active.syntaxStr;
  static Color get syntaxNum => _active.syntaxNum;
  static Color get syntaxCom => _active.syntaxCom;
  static Color get syntaxFn => _active.syntaxFn;
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
