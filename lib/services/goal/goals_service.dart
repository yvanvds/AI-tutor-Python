import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/subtree_backup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class GoalsService {
  GoalsService({CosmosContainer? container}) : _containerOverride = container;

  static const String _pk = CosmosPartitions.goal;
  static const Uuid _uuid = Uuid();

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.goals();

  // --- STREAMS -------------------------------------------------------------

  Stream<List<Goal>>? get streamRoots {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchRoots)),
    );
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
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchAllByTitle)),
    );
  }

  // --- ONE-SHOTS -----------------------------------------------------------

  Future<List<Goal>> getChildrenOnce(String? parentId) =>
      safeCosmos(() => _fetchChildrenOrRoots(parentId));

  Future<Goal?> getGoalOnce(String id) => safeCosmos(() => _fetchGoal(id));

  Future<List<Goal>> getRootGoalsOnce() => safeCosmos(_fetchRoots);

  /// Validation set for AI-emitted concept attributions: union of
  /// `knownConcepts` from [targetRootGoal] and every earlier root goal
  /// (those with a strictly smaller `order`). Pass [cachedRoots] (from
  /// GoalSelectionState) to avoid a Cosmos round-trip on every AI request.
  Future<List<String>> getKnownConceptsInScope(
    Goal targetRootGoal, {
    List<Goal>? cachedRoots,
  }) async {
    final roots = (cachedRoots != null && cachedRoots.isNotEmpty)
        ? cachedRoots
        : await getRootGoalsOnce();
    final out = <String>{};
    for (final root in roots) {
      if (root.order > targetRootGoal.order) break;
      out.addAll(root.knownConcepts);
      if (root.id == targetRootGoal.id) break;
    }
    return out.toList();
  }

  Future<List<Goal>> getAllGoalsOnce() => safeCosmos(_fetchAll);

  // --- CREATE --------------------------------------------------------------

  Future<void> createRoot(String title) async {
    final next = await _nextOrder(parentId: null);
    final goal = Goal(id: _uuid.v4(), title: title, order: next);
    await safeCosmos(
      () => _container.create(_docMap(goal), partitionKey: _pk),
    );
  }

  Future<void> createChild(String parentId, String title) async {
    final next = await _nextOrder(parentId: parentId);
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      parentId: parentId,
      order: next,
    );
    await safeCosmos(
      () => _container.create(_docMap(goal), partitionKey: _pk),
    );
  }

  Future<String> createGoalWithFields({
    required String title,
    String? description,
    String? parentId,
    required int order,
    bool optional = false,
    List<String> suggestions = const [],
    List<String> knownConcepts = const [],
  }) async {
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      description: description,
      parentId: parentId,
      order: order,
      optional: optional,
      suggestions: suggestions,
      knownConcepts: knownConcepts,
    );
    await safeCosmos(
      () => _container.create(_docMap(goal), partitionKey: _pk),
    );
    return goal.id;
  }

  // --- UPDATE --------------------------------------------------------------

  Future<void> updateTitle(String id, String title) =>
      _patch(id, {'title': title});

  Future<void> updateDescription(String id, String? description) =>
      _patch(id, {'description': description});

  Future<void> updateOptional(String id, bool optional) =>
      _patch(id, {'optional': optional});

  Future<void> updateTags(String id, List<String> tags) =>
      _patch(id, {'tags': tags});

  Future<void> updateSuggestions(String id, List<String> suggestions) =>
      _patch(id, {'suggestions': suggestions});

  Future<void> updateKnownConcepts(String id, List<String> knownConcepts) =>
      _patch(id, {'knownConcepts': knownConcepts});

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
    await safeCosmos(
      () => _container.executeBatch(ops, partitionKey: _pk),
    );
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
          'suggestions': g.suggestions,
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
    await safeCosmos(
      () => _container.executeBatch(ops, partitionKey: _pk),
    );
  }

  Future<void> restoreSubtree(SubtreeBackup backup) async {
    if (backup.nodes.isEmpty) return;
    final ops = <BatchOperation>[];
    for (final (id, data) in backup.nodes) {
      ops.add(
        BatchOperation.upsert({
          'id': id,
          'type': _pk,
          ...data,
        }),
      );
    }
    await safeCosmos(
      () => _container.executeBatch(ops, partitionKey: _pk),
    );
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
    final doc = await safeCosmos(
      () => _container.read(id, partitionKey: _pk),
    );
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
    final docs = await _container.query(
      'SELECT * FROM c',
      partitionKey: _pk,
    );
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
    'suggestions': goal.suggestions,
    'knownConcepts': goal.knownConcepts,
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

final goalsServiceProvider = Provider<GoalsService>(
  (_) => GoalsService(),
);
