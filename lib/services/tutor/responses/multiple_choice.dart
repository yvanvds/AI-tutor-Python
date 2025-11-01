/*
{
  "type": "multiple_choice",
  "prompt": "What will this code output?\n\nprint('Python')",
  "options": [
    {"option": "A: Python"},
    {"option": "B: 'Python'"},
    {"option": "C: print('Python')"},
    {"option": "D: Error"}
  ]
}
*/
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class MultipleChoice implements ChatResponse {
  final String type;
  final String prompt;
  final List<String> options;

  MultipleChoice({
    required this.type,
    required this.prompt,
    required this.options,
  });

  factory MultipleChoice.fromMap(Map<String, dynamic> map) {
    return MultipleChoice(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      options:
          (map['options'] as List?)
              ?.map((o) => o['option'] as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'options': options.map((o) => {'option': o}).toList(),
  };
}
