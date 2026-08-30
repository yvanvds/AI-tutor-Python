import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module.dart';

class ModuleService extends Notifier<List<Module>> {
  ModuleService({CosmosContainer? container}) : _containerOverride = container;

  static const String _pk = CosmosPartitions.module;

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.modules();

  @override
  List<Module> build() {
    final sub = watchAll().listen((list) => state = List.unmodifiable(list));
    ref.onDispose(sub.cancel);
    return const [];
  }

  List<Module> get cachedAll => state;

  Stream<List<Module>> watchAll() {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchAll)));
  }

  Future<List<Module>> getAll() => safeCosmos(_fetchAll);

  Future<Module?> getById(String id) => safeCosmos(() => _fetchById(id));

  Future<void> upsert(Module module) async {
    await safeCosmos(
      () => _container.upsert(module.toMap(), partitionKey: _pk),
    );
  }

  /// Idempotent: ensures a single default module exists. Returns its id.
  /// Safe to call from concurrent clients — Cosmos `upsert` collapses races
  /// on the deterministic [Module.defaultId].
  Future<String> ensureDefaultModule() async {
    final existing = await _fetchById(Module.defaultId);
    if (existing != null) return existing.id;
    final fallback = Module(
      id: Module.defaultId,
      title: 'Python basics',
      order: 0,
    );
    await upsert(fallback);
    return fallback.id;
  }

  Future<List<Module>> _fetchAll() async {
    final docs = await _container.query(
      'SELECT * FROM c ORDER BY c["order"]',
      partitionKey: _pk,
    );
    return docs.map(Module.fromCosmos).toList();
  }

  Future<Module?> _fetchById(String id) async {
    final doc = await _container.read(id, partitionKey: _pk);
    if (doc == null) return null;
    return Module.fromCosmos(doc);
  }
}

final moduleServiceProvider = NotifierProvider<ModuleService, List<Module>>(
  ModuleService.new,
);
