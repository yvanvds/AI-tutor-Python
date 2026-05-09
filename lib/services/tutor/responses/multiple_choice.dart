/*
{
  "type": "multiple_choice",
  "prompt": "What will this code output?\n\nprint('Python')",
  "code": "print('Python')",
  "options": [
    {"option": "Python"},
    {"option": "'Python'"},
    {"option": "print('Python')"},
    {"option": "Error"}
  ]
}
*/
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class MultipleChoice implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String code;
  final List<String> options;

  MultipleChoice({
    required this.type,
    required this.prompt,
    required this.options,
    required this.code,
  });

  factory MultipleChoice.fromMap(Map<String, dynamic> map) {
    return MultipleChoice(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
      options:
          (map['options'] as List?)
              ?.map((o) => o['option'] as String)
              .toList() ??
          [],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'code': code,
    'options': options.map((o) => {'option': o}).toList(),
  };
}
