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
  ],
  "correct": "A"
}
*/
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class MultipleChoice implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String code;
  final List<String> options;

  /// The intended answer, as the text of one of [options] (#185) — never a
  /// letter, because the options are shuffled before the student sees them.
  /// `null` when the model named none, or named one that is not an option.
  ///
  /// The question bank stores it as the answer key, and the grading call of
  /// a pick carries it as `correct_option` (#197). [toJson] leaves it out on
  /// purpose: that is the question as it goes on the exercise's history,
  /// which every call on the exercise reads, pick or no pick.
  final String? correct;

  MultipleChoice({
    required this.type,
    required this.prompt,
    required this.options,
    required this.code,
    this.correct,
  });

  factory MultipleChoice.fromMap(Map<String, dynamic> map) {
    final options =
        (map['options'] as List?)?.map((o) => o['option'] as String).toList() ??
        <String>[];
    return MultipleChoice(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
      options: options,
      correct: resolveCorrect(map['correct'], options),
    );
  }

  static final RegExp _letter = RegExp(r'^\(?([A-Za-z])[).:]?$');

  /// The option [raw] names. The `mcQuestion` instructions ask for the
  /// positional letter (`"A"` = the first option), so a lone letter —
  /// `A`, `b`, `C)`, `(D)` — is read as a position first; anything else is
  /// matched against the option texts. A number is ambiguous (0- or
  /// 1-based?) and is not guessed at.
  static String? resolveCorrect(Object? raw, List<String> options) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    final letter = _letter.firstMatch(value);
    if (letter != null) {
      final index =
          letter.group(1)!.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
      if (index < options.length) return options[index];
    }
    for (final option in options) {
      if (option.trim() == value) return option;
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'code': code,
    'options': options.map((o) => {'option': o}).toList(),
  };
}
