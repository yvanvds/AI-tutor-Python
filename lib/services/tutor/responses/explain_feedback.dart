import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

/*
{
  "type": "explain_feedback",
  "quality": "wrong | partial | correct",
  "feedback": "brief explanation of what's missing or why correct",
  "follow_up": "optional new question or prompt to clarify thinking"
}
*/

class ExplainFeedback implements ChatResponse {
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final String? followUp;

  ExplainFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.followUp,
  });

  factory ExplainFeedback.fromMap(Map<String, dynamic> map) {
    return ExplainFeedback(
      type: map['type'] ?? 'explain_feedback',
      quality: _stringToQuality(map['quality']),
      prompt: map['prompt'] ?? '',
      followUp: map['followUp'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'quality': quality.name,
      'feedback': prompt,
      if (followUp != null) 'followUp': followUp,
    };
  }

  static AnswerQuality _stringToQuality(String? value) {
    switch (value?.toLowerCase()) {
      case 'wrong':
        return AnswerQuality.wrong;
      case 'partial':
        return AnswerQuality.partial;
      case 'correct':
        return AnswerQuality.correct;
      default:
        return AnswerQuality.wrong;
    }
  }
}
