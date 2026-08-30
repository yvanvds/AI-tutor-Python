import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/goal/subtree_backup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class GoalsService {
  GoalsService({CosmosContainer? container}) : _containerOverride = container;

  static const String _pk = CosmosPartitions.goal;
  static const Uuid _uuid = Uuid();

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.goals();

  // --- STREAMS -------------------------------------------------------------

  Stream<List<Goal>>? get streamRoots {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchRoots)));
  }

  Stream<Goal?> streamGoal(String id) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchGoal(id))),
    );
  }

  Stream<List<Goal>> streamChildren(String parentId) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchChildren(parentId))),
    );
  }

  Stream<List<Goal>> streamAllGoals() {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchAllByTitle)));
  }

  // --- ONE-SHOTS -----------------------------------------------------------

  Future<List<Goal>> getChildrenOnce(String? parentId) =>
      safeCosmos(() => _fetchChildrenOrRoots(parentId));

  Future<Goal?> getGoalOnce(String id) => safeCosmos(() => _fetchGoal(id));

  Future<List<Goal>> getRootGoalsOnce() => safeCosmos(_fetchRoots);

  Future<List<Goal>> getAllGoalsOnce() => safeCosmos(_fetchAll);

  // --- CREATE --------------------------------------------------------------

  Future<void> createRoot(String title) async {
    final next = await _nextOrder(parentId: null);
    final goal = Goal(id: _uuid.v4(), title: title, order: next);
    await safeCosmos(() => _container.create(_docMap(goal), partitionKey: _pk));
  }

  Future<void> createChild(String parentId, String title) async {
    final next = await _nextOrder(parentId: parentId);
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      parentId: parentId,
      order: next,
    );
    await safeCosmos(() => _container.create(_docMap(goal), partitionKey: _pk));
  }

  Future<String> createGoalWithFields({
    String? id,
    required String title,
    String? description,
    String? parentId,
    required int order,
    bool optional = false,
    List<String> teachingTips = const [],
    bool allowChains = false,
    List<Map<String, dynamic>> objectives = const [],
    String? contentId,
    String moduleId = '',
  }) async {
    final goal = Goal(
      id: id ?? _uuid.v4(),
      title: title,
      description: description,
      parentId: parentId,
      order: order,
      optional: optional,
      teachingTips: teachingTips,
      allowChains: allowChains,
      objectives: objectives
          .map(LearningObjective.fromMap)
          .toList(growable: false),
      contentId: contentId,
      moduleId: moduleId,
    );
    await safeCosmos(() => _container.create(_docMap(goal), partitionKey: _pk));
    return goal.id;
  }

  /// Upserts a goal/subgoal at the given [id]. If a doc with that id already
  /// exists, its `contentId` (the link to the authored Lesinhoud) is carried
  /// over unless the caller passes a non-null [contentId] explicitly. Used by
  /// the "Replace" import path so authored lesson content survives a re-import
  /// of the goal tree.
  Future<void> upsertGoalWithFields({
    required String id,
    required String title,
    String? description,
    String? parentId,
    required int order,
    bool optional = false,
    List<String> teachingTips = const [],
    bool allowChains = false,
    List<Map<String, dynamic>> objectives = const [],
    String? contentId,
    String moduleId = '',
  }) async {
    String? finalContentId = contentId;
    if (finalContentId == null) {
      final existing = await safeCosmos(
        () => _container.read(id, partitionKey: _pk),
      );
      final existingCid = existing?['contentId'];
      if (existingCid is String && existingCid.isNotEmpty) {
        finalContentId = existingCid;
      }
    }

    final goal = Goal(
      id: id,
      title: title,
      description: description,
      parentId: parentId,
      order: order,
      optional: optional,
      teachingTips: teachingTips,
      allowChains: allowChains,
      objectives: objectives
          .map(LearningObjective.fromMap)
          .toList(growable: false),
      contentId: finalContentId,
      moduleId: moduleId,
    );
    await safeCosmos(() => _container.upsert(_docMap(goal), partitionKey: _pk));
  }

  /// Deletes the listed goal docs in a single transactional batch. All goal
  /// docs share the `/type = "goal"` partition, so this is safe.
  Future<void> deleteGoalsByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final ops = ids
        .map((id) => BatchOperation.delete(id))
        .toList(growable: false);
    await safeCosmos(() => _container.executeBatch(ops, partitionKey: _pk));
  }

  // --- UPDATE --------------------------------------------------------------

  Future<void> updateTitle(String id, String title) =>
      _patch(id, {'title': title});

  Future<void> updateDescription(String id, String? description) =>
      _patch(id, {'description': description});

  Future<void> updateOptional(String id, bool optional) =>
      _patch(id, {'optional': optional});

  Future<void> updateKind(String id, String? kind) =>
      _patch(id, {'kind': kind});

  Future<void> updateTags(String id, List<String> tags) =>
      _patch(id, {'tags': tags});

  Future<void> updateTeachingTips(String id, List<String> teachingTips) =>
      _patch(id, {'teachingTips': teachingTips});

  Future<void> updateAllowChains(String id, bool allowChains) =>
      _patch(id, {'allowChains': allowChains});

  Future<void> setContentId(String id, String? contentId) =>
      _patch(id, {'contentId': contentId});

  Future<void> setModuleId(String id, String moduleId) =>
      _patch(id, {'moduleId': moduleId});

  /// Idempotent backfill: any goal whose `moduleId` is empty/missing gets
  /// [defaultModuleId]. All goals share the `/type = "goal"` partition, so
  /// the writes go through a single transactional batch.
  Future<int> backfillModuleIds(String defaultModuleId) async {
    final all = await safeCosmos(_fetchAll);
    final ops = <BatchOperation>[];
    for (final g in all) {
      if (g.moduleId.isNotEmpty) continue;
      final doc = await safeCosmos(
        () => _container.read(g.id, partitionKey: _pk),
      );
      if (doc == null) continue;
      doc['moduleId'] = defaultModuleId;
      ops.add(BatchOperation.upsert(doc));
    }
    if (ops.isEmpty) return 0;
    await safeCosmos(() => _container.executeBatch(ops, partitionKey: _pk));
    return ops.length;
  }

  Future<void> reparent(String id, String? newParentId) async {
    final next = await _nextOrder(parentId: newParentId);
    await _patch(id, {'parentId': newParentId, 'order': next});
  }

  Future<void> applyOrder(String? parentId, List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final ops = <BatchOperation>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final doc = await safeCosmos(
        () => _container.read(id, partitionKey: _pk),
      );
      if (doc == null) continue;
      doc['order'] = (i + 1) * 1000;
      doc['parentId'] = parentId;
      ops.add(BatchOperation.upsert(doc));
    }
    if (ops.isEmpty) return;
    await safeCosmos(() => _container.executeBatch(ops, partitionKey: _pk));
  }

  // --- SUBTREE BACKUP/RESTORE ----------------------------------------------

  Future<SubtreeBackup> backupSubtree(String rootId) async {
    final nodes = await _collectSubtree(rootId);
    final out = <(String, Map<String, dynamic>)>[];
    for (final g in nodes) {
      out.add((
        g.id,
        {
          'title': g.title,
          'description': g.description,
          'parentId': g.parentId,
          'order': g.order,
          'optional': g.optional,
          'teachingTips': g.teachingTips,
          'allowChains': g.allowChains,
          'objectives': g.objectives.map((o) => o.toMap()).toList(),
          'contentId': g.contentId,
          'moduleId': g.moduleId,
        },
      ));
    }
    return SubtreeBackup(out);
  }

  Future<void> deleteSubtree(String rootId) async {
    final nodes = await _collectSubtree(rootId);
    if (nodes.isEmpty) return;
    final ops = nodes
        .map((g) => BatchOperation.delete(g.id))
        .toList(growable: false);
    await safeCosmos(() => _container.executeBatch(ops, partitionKey: _pk));
  }

  Future<void> restoreSubtree(SubtreeBackup backup) async {
    if (backup.nodes.isEmpty) return;
    final ops = <BatchOperation>[];
    for (final (id, data) in backup.nodes) {
      ops.add(BatchOperation.upsert({'id': id, 'type': _pk, ...data}));
    }
    await safeCosmos(() => _container.executeBatch(ops, partitionKey: _pk));
  }

  Future<int> countDescendants(String rootId) async {
    final subtree = await _collectSubtree(rootId);
    return (subtree.length - 1).clamp(0, 1 << 31);
  }

  // --- HELPERS -------------------------------------------------------------

  Future<int> _nextOrder({String? parentId}) async {
    final sql = parentId == null
        ? 'SELECT TOP 1 c["order"] AS o FROM c '
              'WHERE NOT IS_DEFINED(c.parentId) OR IS_NULL(c.parentId) '
              'ORDER BY c["order"] DESC'
        : 'SELECT TOP 1 c["order"] AS o FROM c '
              'WHERE c.parentId = @parentId '
              'ORDER BY c["order"] DESC';
    final results = await safeCosmos(
      () => _container.query(
        sql,
        parameters: parentId == null ? const {} : {'@parentId': parentId},
        partitionKey: _pk,
      ),
    );
    if (results.isEmpty) return 1000;
    final current = (results.first['o'] as int?) ?? 0;
    return current + 1000;
  }

  Future<void> _patch(String id, Map<String, Object?> changes) async {
    final doc = await safeCosmos(() => _container.read(id, partitionKey: _pk));
    if (doc == null) return;
    doc.addAll(changes);
    await safeCosmos(() => _container.replace(id, doc, partitionKey: _pk));
  }

  Future<List<Goal>> _fetchRoots() async {
    final docs = await _container.query(
      'SELECT * FROM c '
      'WHERE NOT IS_DEFINED(c.parentId) OR IS_NULL(c.parentId) '
      'ORDER BY c["order"]',
      partitionKey: _pk,
    );
    return docs.map(Goal.fromCosmos).toList();
  }

  Future<List<Goal>> _fetchChildren(String parentId) async {
    final docs = await _container.query(
      'SELECT * FROM c WHERE c.parentId = @parentId ORDER BY c["order"]',
      parameters: {'@parentId': parentId},
      partitionKey: _pk,
    );
    return docs.map(Goal.fromCosmos).toList();
  }

  Future<List<Goal>> _fetchChildrenOrRoots(String? parentId) =>
      parentId == null ? _fetchRoots() : _fetchChildren(parentId);

  Future<List<Goal>> _fetchAll() async {
    final docs = await _container.query('SELECT * FROM c', partitionKey: _pk);
    return docs.map(Goal.fromCosmos).toList();
  }

  Future<List<Goal>> _fetchAllByTitle() async {
    final docs = await _container.query(
      'SELECT * FROM c ORDER BY c.title',
      partitionKey: _pk,
    );
    return docs.map(Goal.fromCosmos).toList();
  }

  Future<Goal?> _fetchGoal(String id) async {
    final doc = await _container.read(id, partitionKey: _pk);
    if (doc == null) return null;
    return Goal.fromCosmos(doc);
  }

  Map<String, Object?> _docMap(Goal goal) => {
    'id': goal.id,
    'type': _pk,
    'title': goal.title,
    'description': goal.description,
    'parentId': goal.parentId,
    'order': goal.order,
    'optional': goal.optional,
    'teachingTips': goal.teachingTips,
    'allowChains': goal.allowChains,
    'objectives': goal.objectives.map((o) => o.toMap()).toList(),
    'contentId': goal.contentId,
    'moduleId': goal.moduleId,
  };

  Future<Map<String, Goal>> _getAllGoalsMap() async {
    final all = await _fetchAll();
    return {for (final g in all) g.id: g};
  }

  Future<List<Goal>> _collectSubtree(String rootId) async {
    final all = await _getAllGoalsMap();
    final out = <Goal>[];
    final q = <String>[rootId];
    while (q.isNotEmpty) {
      final id = q.removeLast();
      final node = all[id];
      if (node == null) continue;
      out.add(node);
      for (final g in all.values) {
        if (g.parentId == id) q.add(g.id);
      }
    }
    return out;
  }
}

final goalsServiceProvider = Provider<GoalsService>((_) => GoalsService());
