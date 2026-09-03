// Reads / writes the `milestones` Cosmos container (#99). Single partition
// (`/type = "milestone"`), teacher-edited, a handful of docs per year.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'milestone.dart';

class MilestoneService {
  MilestoneService({CosmosContainer? container})
    : _containerOverride = container;

  static const String _pk = CosmosPartitions.milestone;

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.milestones();

  /// Every milestone, earliest due date first.
  Future<List<Milestone>> getAllOnce() => safeCosmos(_fetchAll);

  Stream<List<Milestone>> watchAll() =>
      safeCosmosStream(pollingStream(() => safeCosmos(_fetchAll)));

  Future<Milestone?> getById(String id) => safeCosmos(() async {
    final doc = await _container.read(id, partitionKey: _pk);
    return doc == null ? null : Milestone.fromCosmos(doc);
  });

  Future<void> upsert(Milestone m) async {
    await safeCosmos(() => _container.upsert(m.toMap(), partitionKey: _pk));
  }

  Future<void> delete(String id) async {
    await safeCosmos(() => _container.delete(id, partitionKey: _pk));
  }

  Future<List<Milestone>> _fetchAll() async {
    final docs = await _container.query(
      'SELECT * FROM c ORDER BY c.dueAt',
      partitionKey: _pk,
    );
    final out = docs.map(Milestone.fromCosmos).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return out;
  }
}

final milestoneServiceProvider = Provider<MilestoneService>(
  (ref) => MilestoneService(),
);
