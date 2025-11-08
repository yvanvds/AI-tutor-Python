import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class Answer implements ChatResponse {
  final String type;
  final String prompt;

  Answer({required this.type, required this.prompt});

  factory Answer.fromMap(Map<String, dynamic> map) {
    return Answer(type: map['type'] ?? 'answer', prompt: map['prompt'] ?? '');
  }

  Map<String, dynamic> toJson() => {'type': type, 'prompt': prompt};
}
