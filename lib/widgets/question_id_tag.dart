import 'dart:async';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The hover text on the ID of the student's own question (#216): what the
/// ID is for. In the stand-alone mode there is no teacher to look it up
/// (#267), so it says to mention it in a bug report.
String questionIdTooltip(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context);
  return ref.watch(appModeProvider) is StandaloneMode
      ? l.session_questionId_tooltip_standalone
      : l.session_questionId_tooltip;
}

/// A question's short ID (#216), `#3fa91c`: small, muted, monospace, with a
/// small button that copies it (#304). The same on the header of the
/// student's exercise and on the teacher's card on the Questions page, so
/// the teacher types — or pastes — what the student reads. [id] is a doc id
/// or a content hash ([BankQuestion.shortIdOf]).
class QuestionIdTag extends StatefulWidget {
  const QuestionIdTag(this.id, {super.key, this.tooltip});

  final String id;

  /// What the ID is for, on hover; none when the place says so already.
  final String? tooltip;

  /// The copy button of every tag; find the one of a tag as its descendant.
  static const Key copyKey = Key('question-id-copy');

  /// How long the button shows that the ID was copied.
  static const Duration copiedFor = Duration(seconds: 2);

  @override
  State<QuestionIdTag> createState() => _QuestionIdTagState();
}

class _QuestionIdTagState extends State<QuestionIdTag> {
  bool _copied = false;
  bool _hovering = false;
  Timer? _reset;

  @override
  void didUpdateWidget(QuestionIdTag old) {
    super.didUpdateWidget(old);
    // Another question: its ID was not copied.
    if (old.id != widget.id && _copied) {
      _reset?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  /// The ID as it is shown, with `#`: the lookup on the Questions page takes
  /// it like that. A copy made in the app, so it pastes in the chat (#334).
  Future<void> _copy() async {
    final id = widget.id;
    await InAppClipboard.instance.copy(BankQuestion.shortIdOf(id));
    if (!mounted || id != widget.id) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(QuestionIdTag.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Text(
      BankQuestion.shortIdOf(widget.id),
      style: AppMono.code(
        color: AppColors.fgFaint,
        size: 11.5,
      ).copyWith(height: 1.3),
    );
    final message = widget.tooltip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message == null)
          text
        else
          Tooltip(
            message: message,
            waitDuration: const Duration(milliseconds: 400),
            child: text,
          ),
        const SizedBox(width: 2),
        Tooltip(
          message: _copied
              ? l.questionId_copied_tooltip
              : l.questionId_copy_tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              key: QuestionIdTag.copyKey,
              onTap: _copy,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 16,
                height: 16,
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 12,
                  color: _hovering || _copied
                      ? AppColors.fgMute
                      : AppColors.fgFaint,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
