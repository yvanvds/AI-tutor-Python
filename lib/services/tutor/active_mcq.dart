import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for an in-flight multiple-choice question rendered inside
/// `PracticeView`. Replaces the old chat-message-based MCQ flow: while
/// non-null, `SessionView` hides the chat panel and `PracticeView` swaps
/// its editor/output layout for the MCQ render.
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

  /// Quality returned by the tutor — drives the visual state (correct/
  /// partial → green tint, wrong → red tint) on the picked option.
  final AnswerQuality? feedbackQuality;

  bool get hasFeedback => feedback != null;

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
