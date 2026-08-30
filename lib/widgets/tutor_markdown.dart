import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Markdown renderer for tutor-authored copy: chat bubbles, MCQ prompt and
/// MCQ feedback. Plain prose stays visually identical to the previous
/// `Text`/`SelectableText` rendering — `**bold**`, `*italic*`, lists,
/// links, inline `` `code` `` and fenced code blocks add structure when the
/// model uses them.
///
/// Surfaces that should NOT use this widget:
/// - MCQ option labels (short, code-y, letter badge handles emphasis)
/// - System pills / chips (single short word)
/// - Streaming chat bubbles (already use `instantMarkdown` from
///   `flyer_chat_text_stream_message`)
class TutorMarkdown extends StatelessWidget {
  const TutorMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  /// A getter, not a cached field: `AppColors.fg` follows the active palette
  /// (#32) and a value captured once would keep the other theme's ink.
  static TextStyle get _defaultStyle =>
      TextStyle(color: AppColors.fg, fontSize: 14, height: 1.55);

  @override
  Widget build(BuildContext context) {
    final base = style ?? _defaultStyle;
    return SelectionArea(
      child: GptMarkdown(
        text,
        style: base,
        highlightBuilder: (context, span, _) =>
            _InlineCode(text: span, base: base),
        codeBuilder: (context, language, code, closed) =>
            _CodeBlock(code: code, language: language),
      ),
    );
  }
}

class _InlineCode extends StatelessWidget {
  const _InlineCode({required this.text, required this.base});
  final String text;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final size = (base.fontSize ?? 14) - 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.ink2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: AppMono.code(size: size)),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language});
  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.ink0,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: HighlightView(
        code,
        language: language.isEmpty ? 'python' : language,
        theme: tutorCodeTheme,
        textStyle: AppMono.code(size: 13),
      ),
    );
  }
}
