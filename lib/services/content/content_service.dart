import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content.dart';

class ContentService extends Notifier<List<Content>> {
  ContentService({CosmosContainer? container}) : _containerOverride = container;

  static const String _pk = CosmosPartitions.content;

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.content();

  @override
  List<Content> build() {
    final sub = watchAll().listen((list) => state = List.unmodifiable(list));
    ref.onDispose(sub.cancel);
    return const [];
  }

  /// Latest cached docs; empty until the first poll completes.
  List<Content> get cachedAll => state;

  Stream<List<Content>> watchAll() {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchAll)));
  }

  Stream<Content?> watchById(String id) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchById(id))),
    );
  }

  Future<Content?> getById(String id) => safeCosmos(() => _fetchById(id));

  Future<void> upsert(Content content) async {
    await safeCosmos(
      () => _container.upsert(content.toMap(), partitionKey: _pk),
    );
  }

  Future<void> delete(String id) async {
    await safeCosmos(() => _container.delete(id, partitionKey: _pk));
  }

  /// Moves an orphaned content doc under [targetGoalId], keeping the
  /// "content id mirrors the subgoal id" invariant: the body is upserted as a
  /// new doc with id == [targetGoalId] (overwriting whatever was there), and
  /// the old doc is deleted when its id differs. Returns the new doc.
  ///
  /// The caller is responsible for setting `Goal.contentId` on the target;
  /// this service doesn't know about goals. The cached list is patched
  /// optimistically so the UI doesn't have to wait for the next poll.
  Future<Content> reassign(Content orphan, String targetGoalId) async {
    final moved = Content(
      id: targetGoalId,
      title: orphan.title,
      body: orphan.body,
    );
    await upsert(moved);
    if (orphan.id != targetGoalId) {
      await delete(orphan.id);
    }
    state = List.unmodifiable([
      for (final c in state)
        if (c.id != orphan.id && c.id != targetGoalId) c,
      moved,
    ]);
    return moved;
  }

  Future<List<Content>> _fetchAll() async {
    final docs = await _container.query(
      'SELECT * FROM c ORDER BY c.title',
      partitionKey: _pk,
    );
    return docs.map(Content.fromCosmos).toList();
  }

  Future<Content?> _fetchById(String id) async {
    final doc = await _container.read(id, partitionKey: _pk);
    if (doc == null) return null;
    return Content.fromCosmos(doc);
  }
}

final contentServiceProvider = NotifierProvider<ContentService, List<Content>>(
  ContentService.new,
);
