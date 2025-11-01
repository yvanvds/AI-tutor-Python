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
  final String feedback;
  final String? followUp;

  ExplainFeedback({
    required this.type,
    required this.quality,
    required this.feedback,
    this.followUp,
  });

  factory ExplainFeedback.fromMap(Map<String, dynamic> map) {
    return ExplainFeedback(
      type: map['type'] ?? 'explain_feedback',
      quality: _stringToQuality(map['quality']),
      feedback: map['feedback'] ?? '',
      followUp: map['follow_up'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'quality': quality.name,
      'feedback': feedback,
      if (followUp != null) 'follow_up': followUp,
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
