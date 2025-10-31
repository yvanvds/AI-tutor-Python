class ExplainFeedback {
  final String type;
  final bool correct;
  final String feedback;
  final String? followUp;
  final double progress;

  ExplainFeedback({
    required this.type,
    required this.correct,
    required this.feedback,
    this.followUp,
    required this.progress,
  });

  factory ExplainFeedback.fromMap(Map<String, dynamic> map) {
    return ExplainFeedback(
      type: map['type'] ?? 'explain_feedback',
      correct: map['correct'] ?? false,
      feedback: map['feedback'] ?? '',
      followUp: map['follow up'] ?? map['follow_up'], // support both variants
      progress: (map['progress'] is num)
          ? (map['progress'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'correct': correct,
    'feedback': feedback,
    if (followUp != null) 'follow up': followUp,
    'progress': progress,
  };
}
