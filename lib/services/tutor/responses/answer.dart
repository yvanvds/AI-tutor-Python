class Answer {
  final String type;
  final String answer;
  final double progress;

  Answer({required this.type, required this.answer, required this.progress});

  factory Answer.fromMap(Map<String, dynamic> map) {
    return Answer(
      type: map['type'] ?? 'answer',
      answer: map['answer'] ?? '',
      progress: (map['progress'] is num)
          ? (map['progress'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'answer': answer,
    'progress': progress,
  };
}
