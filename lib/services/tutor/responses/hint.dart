import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class Hint implements ChatResponse {
  final String type;
  final String prompt;

  Hint({required this.type, required this.prompt});

  factory Hint.fromMap(Map<String, dynamic> map) {
    return Hint(type: map['type'] ?? 'prompt', prompt: map['prompt'] ?? '');
  }

  Map<String, dynamic> toJson() => {'type': type, 'prompt': prompt};
}
