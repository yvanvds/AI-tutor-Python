/*
{
  "type": "guiding question",
  "prompt": "What do you think this code does?",
  "code": "print('hi')"
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class GuidingExcercise implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String code;

  GuidingExcercise.guidingExcercise({
    required this.type,
    required this.prompt,
    required this.code,
  });

  factory GuidingExcercise.fromMap(Map<String, dynamic> map) {
    return GuidingExcercise.guidingExcercise(
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
