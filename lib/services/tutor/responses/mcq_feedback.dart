class McqFeedback {
  final String type;
  final bool correct;
  final String explanation;
  final double progress;

  McqFeedback({
    required this.type,
    required this.correct,
    required this.explanation,
    required this.progress,
  });

  factory McqFeedback.fromMap(Map<String, dynamic> map) {
    return McqFeedback(
      type: map['type'] ?? 'mcq_feedback',
      correct: map['correct'] ?? false,
      explanation: map['explanation'] ?? '',
      progress: (map['progress'] is num)
          ? (map['progress'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'correct': correct,
    'explanation': explanation,
    'progress': progress,
  };
}
