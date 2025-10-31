class Hint {
  final String type;
  final String hint;
  final double progress;

  Hint({required this.type, required this.hint, required this.progress});

  factory Hint.fromMap(Map<String, dynamic> map) {
    return Hint(
      type: map['type'] ?? 'hint',
      hint: map['hint'] ?? '',
      progress: (map['progress'] is num)
          ? (map['progress'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'hint': hint,
    'progress': progress,
  };
}
