// Model class representing a Goal.
//
// `Goal` is a unified type for both root goals and subgoals; `parentId == null`
// distinguishes a root from a subgoal. Subgoal-only fields (`teachingTips`,
// `allowChains`, `objectives`, `contentId`) are present on the type for
// every doc but only meaningful on subgoals.

import 'package:ai_tutor_python/services/goal/learning_objective.dart';

class Goal {
  final String id;
  final String title;
  final String? description;
  final String? parentId;
  final int order;
  final bool optional;

  /// Subgoal-only: free-form prose hints to the LLM about how to approach this
  /// subgoal. Surfaced in instruction prompts as `{teachingTips}`.
  final List<String> teachingTips;

  /// Subgoal-only: enables follow-up chains up to depth 2 within this subgoal.
  /// Default `false` — enabled per-subgoal for conceptually rich content.
  final bool allowChains;

  /// Subgoal-only: ordered list of Learning Objectives.
  final List<LearningObjective> objectives;

  /// Reference to a `content` doc holding the authored explanation block for
  /// this subgoal. Null when no block has been authored yet.
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
    this.teachingTips = const [],
    this.allowChains = false,
    this.objectives = const [],
    this.contentId,
    this.moduleId = '',
  });

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'parentId': parentId,
        'order': order,
        'optional': optional,
        'teachingTips': teachingTips,
        'allowChains': allowChains,
        'objectives': objectives.map((o) => o.toMap()).toList(),
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
      teachingTips: List<String>.from(map['teachingTips'] ?? const []),
      allowChains: map['allowChains'] ?? false,
      objectives: (map['objectives'] as List?)
              ?.map((e) => LearningObjective.fromMap(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          const [],
      contentId: map['contentId'] as String?,
      moduleId: (map['moduleId'] as String?) ?? '',
    );
  }

  /// Build from a Cosmos document. The doc carries its own `id` field.
  factory Goal.fromCosmos(Map<String, dynamic> doc) {
    return Goal.fromMap(id: doc['id'] as String, map: doc);
  }
}
