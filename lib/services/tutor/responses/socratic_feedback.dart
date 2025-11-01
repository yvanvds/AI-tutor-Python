import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class SocraticFeedback implements ChatResponse {
  final String type;
  final AnswerQuality quality;
  final String feedback;
  final String? followUp;

  SocraticFeedback({
    required this.type,
    required this.quality,
    required this.feedback,
    this.followUp,
  });

  factory SocraticFeedback.fromMap(Map<String, dynamic> map) {
    return SocraticFeedback(
      type: map['type'] ?? 'socratic_feedback',
      quality: _stringToQuality(map['quality']),
      feedback: map['feedback'] ?? '',
      followUp: map['follow up'] ?? map['follow_up'],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'quality': quality.name,
    'feedback': feedback,
    if (followUp != null) 'follow up': followUp,
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
