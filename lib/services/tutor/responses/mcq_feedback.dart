import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/suspected_concepts.dart';

class McqFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final List<String>? suspectedConcepts;

  McqFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.suspectedConcepts,
  });

  factory McqFeedback.fromMap(Map<String, dynamic> map) {
    return McqFeedback(
      type: map['type'] ?? 'mcq_feedback',
      quality: _stringToQuality(map['quality']),
      prompt: map['prompt'] ?? '',
      suspectedConcepts: parseSuspectedConcepts(map['suspected_concepts']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'quality': quality.name,
    'prompt': prompt,
    if (suspectedConcepts != null) 'suspected_concepts': suspectedConcepts,
  };

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
