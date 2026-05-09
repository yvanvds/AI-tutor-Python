import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';

class SocraticFeedback implements ChatResponse {
  @override
  final String type;
  final AnswerQuality quality;
  final String prompt;
  final List<LoSignal> loSignals;
  final FollowUp? followUp;

  SocraticFeedback({
    required this.type,
    required this.quality,
    required this.prompt,
    this.loSignals = const [],
    this.followUp,
  });

  factory SocraticFeedback.fromMap(Map<String, dynamic> map) {
    return SocraticFeedback(
      type: map['type'] ?? 'socratic_feedback',
      quality: _stringToQuality(map['overallQuality'] ?? map['quality']),
      prompt: map['prompt'] ?? '',
      loSignals: parseLoSignals(map['loSignals']),
      followUp: FollowUp.tryParse(map['followUp']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'overallQuality': quality.name,
    'prompt': prompt,
    'loSignals': loSignals.map((s) => s.toJson()).toList(),
    if (followUp != null) 'followUp': followUp!.toJson(),
  };

  static AnswerQuality _stringToQuality(Object? value) {
    if (value is! String) return AnswerQuality.wrong;
    switch (value.toLowerCase()) {
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
