import 'package:ai_tutor_python/core/answer_quality.dart';

/// One AI-emitted suspected-concept tag captured during a feedback turn.
/// Stored as a bounded recent list on `Progress` so we can audit how well
/// the AI's attribution holds up on real students before wiring any
/// behaviour to it. `quality` is the [AnswerQuality] from the same turn —
/// a `correct` answer that the AI still tags `"variables"` is a very
/// different signal from a `wrong` one.
class ConceptAttribution {
  final String concept;
  final DateTime at;
  final AnswerQuality quality;

  ConceptAttribution({
    required this.concept,
    required this.at,
    required this.quality,
  });

  Map<String, dynamic> toJson() => {
        'concept': concept,
        'at': at.toUtc().toIso8601String(),
        'quality': quality.name,
      };

  factory ConceptAttribution.fromJson(Map<String, dynamic> map) {
    final raw = map['at'];
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    return ConceptAttribution(
      concept: (map['concept'] as String?) ?? '',
      at: parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      quality: _parseQuality(map['quality']),
    );
  }

  static AnswerQuality _parseQuality(Object? raw) {
    if (raw is! String) return AnswerQuality.wrong;
    for (final q in AnswerQuality.values) {
      if (q.name == raw) return q;
    }
    return AnswerQuality.wrong;
  }

  @override
  bool operator ==(Object other) =>
      other is ConceptAttribution &&
      other.concept == concept &&
      other.at.toUtc() == at.toUtc() &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(concept, at.toUtc(), quality);
}
