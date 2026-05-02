import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/suspected_concepts.dart';

class SocraticFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final String? followUp;
  final List<String>? suspectedConcepts;

  SocraticFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.followUp,
    this.suspectedConcepts,
  });

  factory SocraticFeedback.fromMap(Map<String, dynamic> map) {
    return SocraticFeedback(
      type: map['type'] ?? 'socratic_feedback',
      quality: _stringToQuality(map['quality']),
      prompt: map['prompt'] ?? '',
      followUp: map['follow up'] ?? map['follow_up'],
      suspectedConcepts: parseSuspectedConcepts(map['suspected_concepts']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'quality': quality.name,
    'prompt': prompt,
    if (followUp != null) 'follow up': followUp,
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
