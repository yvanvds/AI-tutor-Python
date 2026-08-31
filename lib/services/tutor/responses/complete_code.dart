/*
{
  "type": "complete_code",
  "prompt": "Fill in the missing part so the code prints Hello, world!",
  "code": "print(___)"
}
*/

import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class CompleteCode implements ChatResponse {
  @override
  final String type;
  final String prompt;
  final String code;

  CompleteCode({required this.type, required this.prompt, required this.code});

  /// The gap a student is asked to fill in (#78).
  ///
  /// The convention is stated to the model in the `completeCodeQuestion`
  /// instructions document (the Cosmos copy; exported to
  /// `instructions-export.md` in this repo), under RULES:
  ///
  /// > META.code MUST contain at least one `___` placeholder marking the gap
  /// > the student fills in.
  ///
  /// So the marker is three underscores. The pattern allows a *longer* run
  /// (`____`, `______`) because a model padding the gap to line something up
  /// is the one variant that is still unmistakably a placeholder. It stops at
  /// three deliberately: one and two underscores are ordinary Python
  /// (`my_var`, `__name__`, `_`), and matching those would reject valid
  /// exercises.
  static final RegExp blankMarker = RegExp('_{3,}');

  /// Whether [code] still has something for the student to fill in. A
  /// `complete_code` exercise without a blank is a finished program the
  /// student can only stare at, so the parser rejects it — see
  /// `ChatResponseFactory.fromMap`.
  bool get hasBlank => blankMarker.hasMatch(code);

  factory CompleteCode.fromMap(Map<String, dynamic> map) {
    return CompleteCode(
      type: map['type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    'code': code,
  };
}
