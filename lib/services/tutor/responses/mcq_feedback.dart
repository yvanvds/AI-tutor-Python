import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class McqFeedback implements ChatResponse {
  final String type;
  final AnswerQuality quality;
  final String explanation;

  McqFeedback({
    required this.type,
    required this.quality,
    required this.explanation,
  });

  factory McqFeedback.fromMap(Map<String, dynamic> map) {
    return McqFeedback(
      type: map['type'] ?? 'mcq_feedback',
      quality: _stringToQuality(map['quality']),
      explanation: map['explanation'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'quality': quality.name,
    'explanation': explanation,
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
