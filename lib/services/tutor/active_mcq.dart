import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for an in-flight multiple-choice question rendered inside
/// `PracticeView`. Replaces the old chat-message-based MCQ flow: while
/// non-null, `PracticeView` swaps its editor/output layout for the MCQ
/// render. The chat panel stays (#271): what the student types there is a
/// question about the quiz, never its answer.
class ActiveMcq {
  const ActiveMcq({
    required this.prompt,
    required this.code,
    required this.options,
    this.selected,
    this.feedback,
    this.feedbackQuality,
  });

  final String prompt;
  final String code;
  final List<String> options;

  /// The option the student picked, or null while waiting for a pick.
  final String? selected;

  /// Tutor-provided feedback text shown after the student picks. Null until
  /// `applyMcqFeedback` lands.
  final String? feedback;

  /// Quality returned by the tutor — drives the tint of the picked option
  /// and the feedback panel (#179): blue while null (being assessed), green
  /// for correct, sand for partial, red for wrong.
  final AnswerQuality? feedbackQuality;

  bool get hasFeedback => feedback != null;

  /// The letter the quiz shows on option [index]: A to F, then the number
  /// (`QuizView`). What a student means by "B", so the tutor is told the
  /// options with the same letters (#271).
  static String badgeFor(int index) =>
      index < _badges.length ? _badges[index] : '${index + 1}';

  static const List<String> _badges = ['A', 'B', 'C', 'D', 'E', 'F'];

  /// The options keyed by the letter they carry on screen, in screen order.
  Map<String, String> get optionsByBadge => {
    for (var i = 0; i < options.length; i++) badgeFor(i): options[i],
  };

  ActiveMcq copyWith({
    String? selected,
    String? feedback,
    AnswerQuality? feedbackQuality,
  }) {
    return ActiveMcq(
      prompt: prompt,
      code: code,
      options: options,
      selected: selected ?? this.selected,
      feedback: feedback ?? this.feedback,
      feedbackQuality: feedbackQuality ?? this.feedbackQuality,
    );
  }
}

final activeMcqProvider = StateProvider<ActiveMcq?>((_) => null);
