import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class Hint implements ChatResponse {
  @override
  final String type;
  final String prompt;

  Hint({required this.type, required this.prompt});

  factory Hint.fromMap(Map<String, dynamic> map) {
    return Hint(type: map['type'] ?? 'prompt', prompt: map['prompt'] ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {'type': type, 'prompt': prompt};
}
