/*
{
  "type": "guiding question",
  "prompt": "What do you think this code does?",
  "code": "print('hi')"
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class GuidingExercise implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String code;

  GuidingExercise.guidingExercise({
    required this.type,
    required this.prompt,
    required this.code,
  });

  factory GuidingExercise.fromMap(Map<String, dynamic> map) {
    return GuidingExercise.guidingExercise(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'code': code,
  };
}
