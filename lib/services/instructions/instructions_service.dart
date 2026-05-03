import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'instruction.dart';

class InstructionsService extends Notifier<List<Instruction>> {
  static const String _pk = CosmosPartitions.instruction;

  CosmosContainer get _container => CosmosPaths.instructions();

  @override
  List<Instruction> build() {
    final sub = watchAll().listen((list) => state = List.unmodifiable(list));
    ref.onDispose(sub.cancel);
    return const [];
  }

  /// Synchronous fast-path: latest cached docs, empty until first fetch.
  List<Instruction> get cachedAll => state;

  Stream<List<Instruction>> watchAll() {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchAll)));
  }

  Future<List<Instruction>> getAll() => safeCosmos(_fetchAll);

  Stream<Instruction?> watchById(String id) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchById(id))),
    );
  }

  Future<Instruction?> getById(String id) => safeCosmos(() => _fetchById(id));

  Future<void> upsert(Instruction instruction) async {
    await safeCosmos(
      () => _container.upsert(instruction.toMap(), partitionKey: _pk),
    );
  }

  Future<void> delete(String id) async {
    await safeCosmos(() => _container.delete(id, partitionKey: _pk));
  }

  Future<List<Instruction>> _fetchAll() async {
    final docs = await _container.query(
      'SELECT * FROM c ORDER BY c.updatedAt DESC',
      partitionKey: _pk,
    );
    return docs.map(Instruction.fromCosmos).toList();
  }

  Future<Instruction?> _fetchById(String id) async {
    final doc = await _container.read(id, partitionKey: _pk);
    if (doc == null) return null;
    return Instruction.fromCosmos(doc);
  }
}

final instructionsServiceProvider =
    NotifierProvider<InstructionsService, List<Instruction>>(
  InstructionsService.new,
);
