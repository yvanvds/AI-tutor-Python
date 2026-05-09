/// One Learning Objective embedded in a subgoal's `objectives` list.
///
/// Curriculum-data part of the conductor redesign (see
/// `docs/CURRICULUM_MODEL.md`). `id` is unique within the subgoal and is the
/// stable key student belief is anchored on.
enum LoKind { recall, apply, predict, reason }

class LearningObjective {
  final String id;
  final String statement;
  final LoKind kind;
  final double weight;
  final bool optional;

  const LearningObjective({
    required this.id,
    required this.statement,
    required this.kind,
    this.weight = 1.0,
    this.optional = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'statement': statement,
        'kind': kind.name,
        'weight': weight,
        'optional': optional,
      };

  factory LearningObjective.fromMap(Map<String, dynamic> map) {
    return LearningObjective(
      id: (map['id'] as String?) ?? '',
      statement: (map['statement'] as String?) ?? '',
      kind: _parseKind(map['kind']),
      weight: (map['weight'] is num) ? (map['weight'] as num).toDouble() : 1.0,
      optional: (map['optional'] as bool?) ?? false,
    );
  }

  static LoKind _parseKind(Object? raw) {
    if (raw is! String) return LoKind.apply;
    for (final k in LoKind.values) {
      if (k.name == raw) return k;
    }
    return LoKind.apply;
  }
}
