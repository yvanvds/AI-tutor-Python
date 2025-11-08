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
  final String prompt;
  final double understanding;
  final String followUp;
  final String code;

  GuidingFeedback({
    required this.type,
    required this.prompt,
    required this.understanding,
    required this.followUp,
    required this.code,
  });

  factory GuidingFeedback.fromMap(Map<String, dynamic> map) {
    return GuidingFeedback(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      understanding: (map['understanding'] is num)
          ? (map['understanding'] as num).toDouble()
          : 0.0,
      followUp: map['followUp'] ?? '',
      code: map['code'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'understanding': understanding,
    'followUp': followUp,
    'code': code,
  };
}
