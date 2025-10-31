class SocraticFeedback {
  final String type;
  final bool correct;
  final String feedback;
  final String? followUp;
  final double progress;

  SocraticFeedback({
    required this.type,
    required this.correct,
    required this.feedback,
    this.followUp,
    required this.progress,
  });

  factory SocraticFeedback.fromMap(Map<String, dynamic> map) {
    return SocraticFeedback(
      type: map['type'] ?? 'socratic_feedback',
      correct: map['correct'] ?? false,
      feedback: map['feedback'] ?? '',
      followUp: map['follow up'] ?? map['follow_up'],
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
