/*

{
  "type": "socratic_question",
  "prompt": "Explain why the following line works, and what would happen if we remove the quotes:\n\nprint('Hello')"
}

*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class SocraticQuestion implements ChatResponse {
  final String type;
  final String prompt;

  SocraticQuestion({required this.type, required this.prompt});

  factory SocraticQuestion.fromMap(Map<String, dynamic> map) {
    return SocraticQuestion(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'prompt': prompt};
}
