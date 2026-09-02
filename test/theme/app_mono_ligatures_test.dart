// Issue #83 — JetBrains Mono ships programming ligatures on by default
// (`calt`), so `==`, `!=`, `>=` rendered as single ═ ≠ ≥ glyphs in every
// code surface: quiz code blocks, quiz options, lesson code samples, the
// editor and the terminal. Beginners must see the literal ASCII characters
// they have to type. These pin the `calt`/`liga` disables on every mono
// style and on every syntax-token entry, so a future token can't silently
// re-enable them.

import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// True when [style] explicitly disables both ligature features.
bool stripsLigatures(TextStyle style) {
  final features = style.fontFeatures;
  if (features == null) return false;
  bool disables(String tag) =>
      features.any((f) => f.feature == tag && f.value == 0);
  return disables('calt') && disables('liga');
}

void main() {
  // google_fonts needs a binding to reach the asset bundle, and must not
  // fetch over the network in a headless run.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('every AppMono style disables calt and liga', () {
    final styles = {
      'code': AppMono.code(),
      'code(sized)': AppMono.code(size: 13),
      'output': AppMono.output(),
      'kbd': AppMono.kbd(),
    };
    for (final entry in styles.entries) {
      expect(
        stripsLigatures(entry.value),
        isTrue,
        reason: 'AppMono.${entry.key} would render == as ═',
      );
    }
  });

  test('every syntax-token entry disables calt and liga', () {
    final theme = tutorCodeTheme;
    expect(theme, isNotEmpty);
    for (final entry in theme.entries) {
      expect(
        stripsLigatures(entry.value),
        isTrue,
        reason: "tutorCodeTheme['${entry.key}'] would render == as ═",
      );
    }
  });
}
