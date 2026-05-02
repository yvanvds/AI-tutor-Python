import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/suspected_concepts.dart';

/*
{
  "type": "code_feedback",
  "summary": "brief explanation of correctness or errors",
  "suggestion": "concise next step for improvement",
  "quality": "wrong | partial | correct",
  "suspected_concepts": ["optional", "tags"]
}
*/

class CodeFeedback implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String suggestion;
  final AnswerQuality quality;
  final List<String>? suspectedConcepts;

  CodeFeedback({
    required this.type,
    required this.prompt,
    required this.suggestion,
    required this.quality,
    this.suspectedConcepts,
  });

  factory CodeFeedback.fromMap(Map<String, dynamic> map) {
    return CodeFeedback(
      type: map['type'] ?? 'code_feedback',
      prompt: map['prompt'] ?? '',
      suggestion: map['suggestion'] ?? '',
      quality: _stringToQuality(map['quality']),
      suspectedConcepts: parseSuspectedConcepts(map['suspected_concepts']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'prompt': prompt,
      'suggestion': suggestion,
      'quality': quality.name,
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
