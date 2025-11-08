import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/subtree_backup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

class GoalsService {
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('goals');

  final ValueNotifier<Goal?> selectedRootGoal = ValueNotifier(null);
  final ValueNotifier<Goal?> selectedChildGoal = ValueNotifier(null);

  final ValueNotifier<Goal?> editorSelectedRootGoal = ValueNotifier(null);
  final ValueNotifier<Goal?> editorSelectedGoal = ValueNotifier(null);

  Stream<List<Goal>>? get streamRoots {
    final q = _collection.where('parentId', isNull: true).orderBy('order');
    return safeFirestoreStream(
      q.snapshots().map((s) => s.docs.map(Goal.fromDoc).toList()),
    );
  }

  Stream<Goal?> streamGoal(String id) {
    final dref = _collection.doc(id);
    return safeFirestoreStream(
      dref.snapshots().map((doc) => doc.exists ? Goal.fromDoc(doc) : null),
    );
  }

  Stream<List<Goal>> streamChildren(String parentId) {
    final q = _collection
        .where('parentId', isEqualTo: parentId)
        .orderBy('order');
    return safeFirestoreStream(
      q.snapshots().map((s) => s.docs.map(Goal.fromDoc).toList()),
    );
  }

  Stream<List<Goal>> streamAllGoals() {
    final q = _collection.orderBy('title');
    return safeFirestoreStream(
      q.snapshots().map((s) => s.docs.map(Goal.fromDoc).toList()),
    );
  }

  // --- ONE-SHOTS -----------------------------------------------------------

  /// Read children once (used to compute target list on drop)
  Future<List<Goal>> getChildrenOnce(String? parentId) async {
    Query<Map<String, dynamic>> q = _collection.orderBy('order');
    q = parentId == null
        ? q.where('parentId', isNull: true)
        : q.where('parentId', isEqualTo: parentId);

    final s = await safeFirestore(() => q.get());
    return s.docs.map(Goal.fromDoc).toList();
  }

  Future<Goal?> getGoalOnce(String id) async {
    final d = await safeFirestore(() => _collection.doc(id).get());
    if (!d.exists) return null;
    return Goal.fromDoc(d);
  }

  Future<List<Goal>> getRootGoalsOnce() async {
    final s = await safeFirestore(
      () => _collection.where('parentId', isNull: true).orderBy('order').get(),
    );
    return s.docs.map(Goal.fromDoc).toList();
  }

  /// ---- Create --------------------------------------------------------------

  Future<void> createRoot(String title) async {
    final next = await _nextOrder(parentId: null);
    await _collection.add({'title': title, 'order': next, 'parentId': null});
  }

  Future<void> createChild(String parentId, String title) async {
    final next = await _nextOrder(parentId: parentId);
    await _collection.add({
      'title': title,
      'parentId': parentId,
      'order': next,
    });
  }

  /// ---- Update --------------------------------------------------------------

  Future<void> updateTitle(String id, String title) async {
    await _collection.doc(id).update({'title': title});
  }

  Future<void> updateDescription(String id, String? description) =>
      _collection.doc(id).update({'description': description});

  Future<void> updateOptional(String id, bool optional) =>
      _collection.doc(id).update({'optional': optional});

  Future<void> updateTags(String id, List<String> tags) =>
      _collection.doc(id).update({'tags': tags});

  Future<void> updateSuggestions(String id, List<String> suggestions) =>
      _collection.doc(id).update({'suggestions': suggestions});

  Future<void> updateKnownConcepts(String id, List<String> knownConcepts) =>
      _collection.doc(id).update({'knownConcepts': knownConcepts});

  /// Change the parent of a goal.
  Future<void> reparent(String id, String? newParentId) async {
    // place at end of new parent's list (or roots)
    final next = await _nextOrder(parentId: newParentId);
    await _collection.doc(id).update({'parentId': newParentId, 'order': next});
  }

  Future<void> applyOrder(String? parentId, List<String> orderedIds) async {
    final batch = FirebaseFirestore.instance.batch();
    // compact with spacing 1000 to keep room for future inserts
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final doc = _collection.doc(id);
      batch.update(doc, {'order': (i + 1) * 1000, 'parentId': parentId});
    }
    await batch.commit();
  }

  /// ---- Helpers -------------------------------------------------------------

  /// Get the next order value for a new child under [parentId].
  Future<int> _nextOrder({String? parentId}) async {
    try {
      Query<Map<String, dynamic>> q = _collection
          .orderBy('order', descending: true)
          .limit(1);
      q = parentId == null
          ? q.where('parentId', isNull: true)
          : q.where('parentId', isEqualTo: parentId);

      final snap = await q.get();
      final currentMax = snap.docs.isEmpty
          ? 0
          : (snap.docs.first.data()['order'] as int? ?? 0);
      return currentMax + 1000;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        // Fallback: put new item at end with a safe default
        // (still unique; we’ll normalize during drag-reorder later)
        return DateTime.now().millisecondsSinceEpoch;
      }
      rethrow;
    }
  }

  /// Load *all* goals once (≤100 so it's fine) and build a map by id.
  Future<Map<String, Goal>> _getAllGoalsMap() async {
    final s = await _collection.get();
    final map = <String, Goal>{};
    for (final d in s.docs) {
      map[d.id] = Goal.fromDoc(d);
    }
    return map;
  }

  /// Collect the subtree (root+descendants) under [rootId].
  Future<List<Goal>> _collectSubtree(String rootId) async {
    final all = await _getAllGoalsMap();
    final List<Goal> out = [];
    final q = <String>[rootId];
    while (q.isNotEmpty) {
      final id = q.removeLast();
      final node = all[id];
      if (node == null) continue;
      out.add(node);
      // push children
      for (final g in all.values) {
        if (g.parentId == id) q.add(g.id);
      }
    }
    return out;
  }

  /// Backup the subtree as raw maps so we can restore 1:1 (same ids).
  Future<SubtreeBackup> backupSubtree(String rootId) async {
    final nodes = await _collectSubtree(rootId);
    final out = <(String, Map<String, dynamic>)>[];
    for (final g in nodes) {
      out.add((
        g.id,
        {
          'title': g.title,
          'description': g.description,
          'parentId': g.parentId, // may be null
          'order': g.order,
          'optional': g.optional,
          'suggestions': g.suggestions,
        },
      ));
    }
    return SubtreeBackup(out);
  }

  /// Delete every node in the subtree (root first/last doesn't matter in batch).
  Future<void> deleteSubtree(String rootId) async {
    final nodes = await _collectSubtree(rootId);
    final batch = FirebaseFirestore.instance.batch();
    for (final g in nodes) {
      batch.delete(_collection.doc(g.id));
    }
    await batch.commit();
  }

  /// Restore a previously backed-up subtree (same ids).
  Future<void> restoreSubtree(SubtreeBackup backup) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final (id, data) in backup.nodes) {
      batch.set(_collection.doc(id), data, SetOptions(merge: false));
    }
    await batch.commit();
  }

  /// Convenience: count descendants (excludes the root).
  Future<int> countDescendants(String rootId) async {
    final subtree = await _collectSubtree(rootId);
    return (subtree.length - 1).clamp(0, 1 << 31);
  }
}
