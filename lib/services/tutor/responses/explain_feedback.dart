import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/suspected_concepts.dart';

/*
{
  "type": "explain_feedback",
  "quality": "wrong | partial | correct",
  "feedback": "brief explanation of what's missing or why correct",
  "follow_up": "optional new question or prompt to clarify thinking",
  "suspected_concepts": ["optional", "tags"]
}
*/

class ExplainFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final String? followUp;
  final List<String>? suspectedConcepts;

  ExplainFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.followUp,
    this.suspectedConcepts,
  });

  factory ExplainFeedback.fromMap(Map<String, dynamic> map) {
    return ExplainFeedback(
      type: map['type'] ?? 'explain_feedback',
      quality: _stringToQuality(map['quality']),
      prompt: map['prompt'] ?? '',
      followUp: map['followUp'],
      suspectedConcepts: parseSuspectedConcepts(map['suspected_concepts']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'quality': quality.name,
      'feedback': prompt,
      if (followUp != null) 'followUp': followUp,
      if (suspectedConcepts != null) 'suspected_concepts': suspectedConcepts,
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
