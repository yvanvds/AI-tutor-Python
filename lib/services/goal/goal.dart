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

  Goal({
    required this.id,
    required this.title,
    this.description,
    this.parentId,
    required this.order,
    this.optional = false,
    this.suggestions = const [],
    this.knownConcepts = const [],
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'parentId': parentId,
    'order': order,
    'optional': optional,
    'suggestions': suggestions,
    'knownConcepts': knownConcepts,
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
    );
  }

  /// Build from a Cosmos document. The doc carries its own `id` field.
  factory Goal.fromCosmos(Map<String, dynamic> doc) {
    return Goal.fromMap(id: doc['id'] as String, map: doc);
  }
}
