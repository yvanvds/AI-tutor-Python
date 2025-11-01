/*
{
  "type": "complete_code",
  "prompt": "Fill in the missing part so the code prints Hello, world!",
  "code": "print(___)"
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class CompleteCode implements ChatResponse {
  final String type;
  final String prompt;
  final String code;

  CompleteCode({required this.type, required this.prompt, required this.code});

  factory CompleteCode.fromMap(Map<String, dynamic> map) {
    return CompleteCode(
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
