/*
{
  "type": "guiding_feedback",
  "feedback": "Encouraging short message about the answer.",
  "understanding": 0.0,
  "prompt": "Next question",
  "code": "Code that goes with the question"  
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class GuidingFeedback implements ChatResponse {
  @override
  final String type;
  final String feedback;
  final double understanding;
  final String prompt;
  final String code;

  GuidingFeedback({
    required this.type,
    required this.feedback,
    required this.understanding,
    required this.prompt,
    required this.code,
  });

  factory GuidingFeedback.fromMap(Map<String, dynamic> map) {
    return GuidingFeedback(
      type: map['type'] ?? '',
      feedback: map['feedback'] ?? '',
      understanding: (map['understanding'] is num)
          ? (map['understanding'] as num).toDouble()
          : 0.0,
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'feedback': feedback,
    'understanding': understanding,
    'prompt': prompt,
    'code': code,
  };
}
