// Model class representing a Goal.
class Goal {
  final String id;
  final String title;
  final String? description;
  final String? parentId;
  final int order;
  final bool optional;
  final List<String> suggestions;
  final List<String> knownConcepts;

  /// Reference to a `content` doc holding the authored explanation block for
  /// this subgoal. Null when no block has been authored yet (transient
  /// during authoring; target state is non-null for every leaf subgoal).
  final String? contentId;

  /// Parent module id. Empty string means "not yet backfilled" — the
  /// Lesinhoud view treats those goals as belonging to the default module.
  final String moduleId;

  Goal({
    required this.id,
    required this.title,
    this.description,
    this.parentId,
    required this.order,
    this.optional = false,
    this.suggestions = const [],
    this.knownConcepts = const [],
    this.contentId,
    this.moduleId = '',
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'parentId': parentId,
    'order': order,
    'optional': optional,
    'suggestions': suggestions,
    'knownConcepts': knownConcepts,
    'contentId': contentId,
    'moduleId': moduleId,
  };

  factory Goal.fromMap({
    required String id,
    required Map<String, dynamic> map,
  }) {
    return Goal(
      id: id,
      title: map['title'] ?? '',
      description: map['description'],
      parentId: map['parentId'],
      order: map['order'] ?? 0,
      optional: map['optional'] ?? false,
      suggestions: List<String>.from(map['suggestions'] ?? []),
      knownConcepts: List<String>.from(map['knownConcepts'] ?? []),
      contentId: map['contentId'] as String?,
      moduleId: (map['moduleId'] as String?) ?? '',
    );
  }

  /// Build from a Cosmos document. The doc carries its own `id` field.
  factory Goal.fromCosmos(Map<String, dynamic> doc) {
    return Goal.fromMap(id: doc['id'] as String, map: doc);
  }
}
