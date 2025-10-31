class CodeFeedback {
  final String type;
  final String summary;
  final String suggestion;
  final double progress;
  final bool correct;

  CodeFeedback({
    required this.type,
    required this.summary,
    required this.suggestion,
    required this.progress,
    required this.correct,
  });

  factory CodeFeedback.fromMap(Map<String, dynamic> map) {
    return CodeFeedback(
      type: map['type'] ?? 'code_feedback',
      summary: map['summary'] ?? '',
      suggestion: map['suggestion'] ?? '',
      correct: map['correct'] ?? false,
      progress: (map['progress'] is num)
          ? (map['progress'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'summary': summary,
    'suggestion': suggestion,
    'progress': progress,
    'correct': correct,
  };
}
