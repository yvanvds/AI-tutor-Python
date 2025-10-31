class Exercise {
  final String type;
  final String exerciseType;
  final String prompt;
  final String? code;
  final List<ExerciseOption> options;
  final String? correctOption;
  final List<String>? checks;
  final String difficulty;

  Exercise({
    required this.type,
    required this.exerciseType,
    required this.prompt,
    this.code,
    this.options = const [],
    this.correctOption,
    this.checks,
    required this.difficulty,
  });

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      type: map['type'] ?? '',
      exerciseType: map['exercise_type'] ?? '',
      prompt: map['prompt'] ?? '',
      code: map['code'],
      options:
          (map['options'] as List?)
              ?.map((o) => ExerciseOption.fromMap(o))
              .toList() ??
          [],
      correctOption: map['correct_option'],
      checks: (map['checks'] as List?)?.map((e) => e.toString()).toList(),
      difficulty: map['difficulty'] ?? 'easy',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'exercise_type': exerciseType,
    'prompt': prompt,
    if (code != null) 'code': code,
    'options': options.map((o) => o.toJson()).toList(),
    if (correctOption != null) 'correct_option': correctOption,
    if (checks != null) 'checks': checks,
    'difficulty': difficulty,
  };
}

class ExerciseOption {
  final String id;
  final String text;

  ExerciseOption({required this.id, required this.text});

  factory ExerciseOption.fromMap(Map<String, dynamic> map) {
    return ExerciseOption(id: map['id'] ?? '', text: map['text'] ?? '');
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}
