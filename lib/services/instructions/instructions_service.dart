import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';

import 'instruction.dart';

class InstructionsService {
  static const String _pk = CosmosPartitions.instruction;

  CosmosContainer get _container => CosmosPaths.instructions();

  /// Stream all instruction docs (poll-based, see TODO.md).
  Stream<List<Instruction>> watchAll() {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchAll)),
    );
  }

  /// One-shot fetch of all docs.
  Future<List<Instruction>> getAll() => safeCosmos(_fetchAll);

  /// Stream a single doc by id (null if it doesn't exist).
  Stream<Instruction?> watchById(String id) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchById(id))),
    );
  }

  /// One-shot fetch a single doc (null if not found).
  Future<Instruction?> getById(String id) =>
      safeCosmos(() => _fetchById(id));

  /// Upsert: create or update the doc. Cosmos upsert replaces the whole
  /// doc — there is no merge semantics here, but the model's `toMap`
  /// already carries every field.
  Future<void> upsert(Instruction instruction) async {
    await safeCosmos(
      () => _container.upsert(instruction.toMap(), partitionKey: _pk),
    );
  }

  Future<void> delete(String id) async {
    await safeCosmos(
      () => _container.delete(id, partitionKey: _pk),
    );
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
