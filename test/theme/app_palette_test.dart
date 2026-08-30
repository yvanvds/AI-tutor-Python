// Issue #32 — the app grew a second token set. These guard the two things
// that can silently rot: a token that exists in only one palette, and a
// derived style (ThemeData, the syntax map) that caches one palette's colours
// and keeps serving them after a switch.

import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Relative luminance, for "is this actually a light/dark colour" assertions.
double _lum(Color c) => c.computeLuminance();

void main() {
  // `buildAppTheme` and the syntax map go through google_fonts, which needs a
  // binding to reach the asset bundle — and must not fall back to fetching
  // over the network when a headless test run cannot see the bundled fonts.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  tearDown(() => AppColors.use(AppPalette.dark));

  test('dark is the palette the app boots with', () {
    expect(AppColors.palette, AppPalette.dark);
    expect(AppColors.ink0, AppPalette.dark.ink0);
  });

  test('AppColors follows the active palette', () {
    AppColors.use(AppPalette.light);
    expect(AppColors.ink0, AppPalette.light.ink0);
    expect(AppColors.fg, AppPalette.light.fg);
    expect(AppColors.syntaxKw, AppPalette.light.syntaxKw);

    AppColors.use(AppPalette.dark);
    expect(AppColors.ink0, AppPalette.dark.ink0);
  });

  test('the two palettes agree on which end of the ramp is the canvas', () {
    // ink0 is always the canvas and fg always the text on it, so every usage
    // site keeps its meaning across the switch.
    expect(_lum(AppPalette.dark.ink0), lessThan(_lum(AppPalette.dark.fg)));
    expect(_lum(AppPalette.light.ink0), greaterThan(_lum(AppPalette.light.fg)));
    expect(AppPalette.dark.brightness, Brightness.dark);
    expect(AppPalette.light.brightness, Brightness.light);
  });

  test('the light palette is genuinely light, and inverts the ramp', () {
    expect(_lum(AppPalette.light.ink0), greaterThan(0.5));
    expect(_lum(AppPalette.dark.ink0), lessThan(0.1));
    // `paper` is the odd one out: it is the inverse card, so it flips too.
    expect(_lum(AppPalette.light.paper), lessThan(0.1));
    expect(_lum(AppPalette.dark.paper), greaterThan(0.5));
  });

  test('every token differs between the palettes', () {
    // A token forgotten in the light set would show as dark ink on paper.
    Map<String, Color> tokens(AppPalette p) => {
      'ink0': p.ink0,
      'ink1': p.ink1,
      'ink2': p.ink2,
      'ink3': p.ink3,
      'ink4': p.ink4,
      'paper': p.paper,
      'fg': p.fg,
      'fgMute': p.fgMute,
      'fgFaint': p.fgFaint,
      'accent': p.accent,
      'accent2': p.accent2,
      'accent3': p.accent3,
      'danger': p.danger,
      'syntaxKw': p.syntaxKw,
      'syntaxStr': p.syntaxStr,
      'syntaxNum': p.syntaxNum,
      'syntaxCom': p.syntaxCom,
      'syntaxFn': p.syntaxFn,
    };
    final dark = tokens(AppPalette.dark);
    final light = tokens(AppPalette.light);
    for (final name in dark.keys) {
      expect(light[name], isNot(dark[name]), reason: '$name is not themed');
    }
  });

  test('accents stay readable on their own canvas', () {
    for (final p in [AppPalette.dark, AppPalette.light]) {
      for (final accent in [p.accent, p.accent2, p.accent3, p.danger]) {
        final contrast = (_lum(accent) - _lum(p.ink0)).abs();
        expect(
          contrast,
          greaterThan(0.1),
          reason: 'accent vanishes into the canvas in ${p.brightness}',
        );
      }
    }
  });

  // `buildAppTheme` itself is exercised end-to-end in
  // `integration_test/flows/options_panel.dart`, which runs the real app: its
  // text theme pulls Inter Tight over the network, which a headless unit test
  // cannot do. The colour half is pure and is checked here.
  group('buildAppColorScheme', () {
    test('maps the palette it is handed onto Material slots', () {
      final light = buildAppColorScheme(AppPalette.light);
      expect(light.brightness, Brightness.light);
      expect(light.primary, AppPalette.light.accent);
      expect(light.surface, AppPalette.light.ink1);
      expect(light.surfaceContainerLowest, AppPalette.light.ink0);
      expect(light.onSurface, AppPalette.light.fg);
      expect(light.error, AppPalette.light.danger);

      final dark = buildAppColorScheme(AppPalette.dark);
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, AppPalette.dark.accent);
      expect(dark.surfaceContainerLowest, AppPalette.dark.ink0);
    });

    test('the two schemes share no colour slot', () {
      final light = buildAppColorScheme(AppPalette.light);
      final dark = buildAppColorScheme(AppPalette.dark);
      expect(light.primary, isNot(dark.primary));
      expect(light.surface, isNot(dark.surface));
      expect(light.onSurface, isNot(dark.onSurface));
    });
  });

  test('the syntax theme is rebuilt per palette, not cached', () {
    // Reading it first under dark used to be enough to freeze it: it was a
    // top-level `final` map.
    expect(tutorCodeTheme['keyword']!.color, AppPalette.dark.syntaxKw);
    AppColors.use(AppPalette.light);
    expect(tutorCodeTheme['keyword']!.color, AppPalette.light.syntaxKw);
    expect(tutorCodeTheme['root']!.backgroundColor, AppPalette.light.ink0);
  });
}
