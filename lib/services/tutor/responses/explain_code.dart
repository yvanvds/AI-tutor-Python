/*
{
  "type": "explain_code",
  "prompt": "What does this code do?",
  "code": "print('Hello, world!')"
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class ExplainCode implements ChatResponse {
  final String type;
  final String prompt;
  final String code;

  ExplainCode({required this.type, required this.prompt, required this.code});

  factory ExplainCode.fromMap(Map<String, dynamic> map) {
    return ExplainCode(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'code': code,
  };
}
