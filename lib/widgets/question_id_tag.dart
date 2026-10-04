import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// A question's short ID (#216), `#3fa91c`: small, muted, monospace. The
/// same on the header of the student's exercise and on the teacher's card
/// on the Questions page, so the teacher types what they read. [id] is a
/// doc id or a content hash ([BankQuestion.shortIdOf]).
class QuestionIdTag extends StatelessWidget {
  const QuestionIdTag(this.id, {super.key, this.tooltip});

  final String id;

  /// What the ID is for, on hover; none when the place says so already.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      BankQuestion.shortIdOf(id),
      style: AppMono.code(
        color: AppColors.fgFaint,
        size: 11.5,
      ).copyWith(height: 1.3),
    );
    final message = tooltip;
    return message == null
        ? text
        : Tooltip(
            message: message,
            waitDuration: const Duration(milliseconds: 400),
            child: text,
          );
  }
}
