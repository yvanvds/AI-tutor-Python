class Instruction {
  Instruction({required this.id, required this.sections, this.updatedAt});

  /// Cosmos doc id, e.g. "system_prompt"
  final String id;

  /// Flexible bag of text sections. Example keys:
  /// current_context, supported_request_types, supported_exercise_types,
  /// response_formats, progress_semantics, rules_and_style, summary
  final Map<String, String> sections;

  final DateTime? updatedAt;

  Instruction copyWith({
    String? id,
    Map<String, String>? sections,
    DateTime? updatedAt,
  }) {
    return Instruction(
      id: id ?? this.id,
      sections: sections ?? this.sections,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serialize for Cosmos. The caller writes this map under the doc's
  /// `id` and partition-key (`type: "instruction"`); both fields are
  /// added here so callers don't have to re-add them.
  Map<String, dynamic> toMap() => {
    'id': id,
    'type': 'instruction',
    'sections': sections,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  static Instruction fromMap(String id, Map<String, dynamic> data) {
    final raw = data['updatedAt'];
    DateTime? parsedAt;
    if (raw is String && raw.isNotEmpty) {
      parsedAt = DateTime.tryParse(raw);
    }
    return Instruction(
      id: id,
      sections:
          (data['sections'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          ) ??
          <String, String>{},
      updatedAt: parsedAt,
    );
  }

  /// Build from a Cosmos document (which already contains its own `id`).
  factory Instruction.fromCosmos(Map<String, dynamic> doc) {
    return Instruction.fromMap(doc['id'] as String, doc);
  }
}
