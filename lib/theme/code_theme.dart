import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'tokens.dart';

/// Syntax highlighting theme for `flutter_highlight` / `flutter_code_editor`.
///
/// Replaces `monokai-sublime` with a palette aligned to the new ink + leaf
/// design tokens. Used by the editor and by the chat code bubble.
///
/// A getter rather than a `final` map: the syntax hues differ per palette
/// (#32), and a map built once at first access would keep the colours of
/// whichever theme happened to be active when the first snippet rendered.
///
/// Every entry is routed through [_token] (the root through [AppMono.code]),
/// which pins JetBrains Mono with its `calt`/`liga` ligatures disabled (#83)
/// — a bare `TextStyle` or direct `GoogleFonts.jetBrainsMono(...)` entry
/// added later would silently bring `==` → ═ back on that token.
Map<String, TextStyle> get tutorCodeTheme => {
  'root': AppMono.code().copyWith(backgroundColor: AppColors.ink0),
  // Not italic (#84): a trailing space typed at the end of an italic span
  // (before a newline) leaves the caret stuck until the next non-space
  // character — students read that as a broken spacebar. Reproduced with
  // the italic font file and with synthesized italic alike, so no token may
  // be italic. Colour alone distinguishes comments.
  'comment': _token(AppColors.syntaxCom),
  'quote': _token(AppColors.syntaxCom),

  'keyword': _token(AppColors.syntaxKw),
  'selector-tag': _token(AppColors.syntaxKw),
  'literal': _token(AppColors.syntaxKw),
  'type': _token(AppColors.syntaxKw),

  'string': _token(AppColors.syntaxStr),
  'doctag': _token(AppColors.syntaxStr),
  'regexp': _token(AppColors.syntaxStr),

  'number': _token(AppColors.syntaxNum),
  'symbol': _token(AppColors.syntaxNum),
  'bullet': _token(AppColors.syntaxNum),

  'title': _token(AppColors.syntaxFn),
  'function': _token(AppColors.syntaxFn),
  'built_in': _token(AppColors.syntaxFn),
  'name': _token(AppColors.syntaxFn),

  'meta': _token(AppColors.accent2),
  'attr': _token(AppColors.accent3),
  'attribute': _token(AppColors.accent3),

  'class': _token(AppColors.syntaxFn, weight: FontWeight.w600),
  'variable': _token(AppColors.fg),
  'template-variable': _token(AppColors.fg),
  'params': _token(AppColors.fg),

  'addition': _token(
    AppColors.accent2,
    background: AppColors.accent2.withValues(alpha: 0.12),
  ),
  'deletion': _token(
    AppColors.danger,
    background: AppColors.danger.withValues(alpha: 0.12),
  ),

  'operator': _token(AppColors.fgMute),
  'punctuation': _token(AppColors.fgMute),
};

/// The single way a token style is built: JetBrains Mono with ligatures off.
// There is deliberately no `italic:` option here (#84): typing a space at
// the end of an italic span (before a newline) does not move the caret
// until the next glyph is typed. `code_theme_caret_test.dart` pins this.
TextStyle _token(Color color, {FontWeight? weight, Color? background}) {
  final style = GoogleFonts.jetBrainsMono(
    color: color,
    backgroundColor: background,
    fontFeatures: AppMono.noLigatures,
  );
  // The weight goes on via `copyWith`, NOT into the google_fonts call:
  // passing it there makes google_fonts load a separate SemiBold font file,
  // which is neither bundled (google_fonts/ ships only Regular + Italic)
  // nor fetchable in a headless test run. Applied here, the engine
  // synthesizes the weight from the regular face — exactly what the old
  // bare `TextStyle(fontWeight: ...)` entries did.
  return weight == null ? style : style.copyWith(fontWeight: weight);
}
