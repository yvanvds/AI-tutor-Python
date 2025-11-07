// lib/data/instructions/instruction.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Instruction {
  Instruction({required this.id, required this.sections, this.updatedAt});

  /// Firestore doc id, e.g. "system_prompt"
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

  Map<String, dynamic> toMap() => {
    'sections': sections,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Instruction fromMap(String id, Map<String, dynamic> data) {
    return Instruction(
      id: id,
      sections:
          (data['sections'] as Map?)?.cast<String, String>() ??
          <String, String>{},
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
