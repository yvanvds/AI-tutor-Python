/*
{
  "type": "write_code",
  "prompt": "Write a Python program that prints your name to the screen."
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class WriteCode implements ChatResponse {
  final String type;
  final String prompt;

  WriteCode({required this.type, required this.prompt});

  factory WriteCode.fromMap(Map<String, dynamic> map) {
    return WriteCode(type: map['type'] ?? '', prompt: map['prompt'] ?? '');
  }

  Map<String, dynamic> toJson() => {'type': type, 'prompt': prompt};
}
