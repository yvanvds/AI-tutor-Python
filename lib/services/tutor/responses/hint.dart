import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class Hint implements ChatResponse {
  final String type;
  final String hint;

  Hint({required this.type, required this.hint});

  factory Hint.fromMap(Map<String, dynamic> map) {
    return Hint(type: map['type'] ?? 'hint', hint: map['hint'] ?? '');
  }

  Map<String, dynamic> toJson() => {'type': type, 'hint': hint};
}
