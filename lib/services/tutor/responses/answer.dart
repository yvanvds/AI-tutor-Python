import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class Answer implements ChatResponse {
  final String type;
  final String answer;

  Answer({required this.type, required this.answer});

  factory Answer.fromMap(Map<String, dynamic> map) {
    return Answer(type: map['type'] ?? 'answer', answer: map['answer'] ?? '');
  }

  Map<String, dynamic> toJson() => {'type': type, 'answer': answer};
}
