import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Syntax highlighting theme for `flutter_highlight` / `flutter_code_editor`.
///
/// Replaces `monokai-sublime` with a palette aligned to the new ink + leaf
/// design tokens. Used by the editor and by the chat code bubble.
///
/// A getter rather than a `final` map: the syntax hues differ per palette
/// (#32), and a map built once at first access would keep the colours of
/// whichever theme happened to be active when the first snippet rendered.
Map<String, TextStyle> get tutorCodeTheme => {
  'root': GoogleFonts.jetBrainsMono(
    backgroundColor: AppColors.ink0,
    color: AppColors.fg,
    fontSize: 14,
    height: 1.6,
  ),
  'comment': GoogleFonts.jetBrainsMono(
    color: AppColors.syntaxCom,
    fontStyle: FontStyle.italic,
  ),
  'quote': GoogleFonts.jetBrainsMono(
    color: AppColors.syntaxCom,
    fontStyle: FontStyle.italic,
  ),

  'keyword': TextStyle(color: AppColors.syntaxKw),
  'selector-tag': TextStyle(color: AppColors.syntaxKw),
  'literal': TextStyle(color: AppColors.syntaxKw),
  'type': TextStyle(color: AppColors.syntaxKw),

  'string': TextStyle(color: AppColors.syntaxStr),
  'doctag': TextStyle(color: AppColors.syntaxStr),
  'regexp': TextStyle(color: AppColors.syntaxStr),

  'number': TextStyle(color: AppColors.syntaxNum),
  'symbol': TextStyle(color: AppColors.syntaxNum),
  'bullet': TextStyle(color: AppColors.syntaxNum),

  'title': TextStyle(color: AppColors.syntaxFn),
  'function': TextStyle(color: AppColors.syntaxFn),
  'built_in': TextStyle(color: AppColors.syntaxFn),
  'name': TextStyle(color: AppColors.syntaxFn),

  'meta': TextStyle(color: AppColors.accent2),
  'attr': TextStyle(color: AppColors.accent3),
  'attribute': TextStyle(color: AppColors.accent3),

  'class': TextStyle(color: AppColors.syntaxFn, fontWeight: FontWeight.w600),
  'variable': TextStyle(color: AppColors.fg),
  'template-variable': TextStyle(color: AppColors.fg),
  'params': TextStyle(color: AppColors.fg),

  'addition': TextStyle(
    color: AppColors.accent2,
    backgroundColor: AppColors.accent2.withValues(alpha: 0.12),
  ),
  'deletion': TextStyle(
    color: AppColors.danger,
    backgroundColor: AppColors.danger.withValues(alpha: 0.12),
  ),

  'operator': TextStyle(color: AppColors.fgMute),
  'punctuation': TextStyle(color: AppColors.fgMute),
};
