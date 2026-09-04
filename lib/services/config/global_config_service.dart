import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'global_config.dart';

class GlobalConfigService extends Notifier<GlobalConfig?> {
  /// [container] is the test seam the other Cosmos-backed services here have
  /// (`InstructionsService`, `GoalsService`, …): production leaves it null and
  /// the service resolves the process-wide `CosmosPaths` handle, a test passes
  /// an `InMemoryCosmos().container` so [setModel] can be driven without a
  /// live database (#118).
  GlobalConfigService({CosmosContainer? container})
    : _containerOverride = container;

  static const String _pk = CosmosPartitions.config;
  static const String _docId = CosmosDocId.globalConfig;

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.config();

  @override
  GlobalConfig? build() {
    final sub = watchConfig().listen((cfg) => state = cfg);
    ref.onDispose(sub.cancel);
    return null;
  }

  /// Synchronous fast-path for hot callers (e.g. the AI request loop).
  GlobalConfig? get cachedConfig => state;

  Future<GlobalConfig?> getConfig() => safeCosmos(_fetchOnce);

  Stream<GlobalConfig?> watchConfig() {
    return safeCosmosStream(pollingStream(() => safeCosmos(_fetchOnce)));
  }

  /// Points the whole school at [model] by writing the single `global` doc
  /// in the `config` container (#118).
  ///
  /// Read-modify-write, never a blind upsert: `GlobalConfig.toMap()`
  /// serialises `ApiKey` as well, so writing a config assembled from anything
  /// less than what is stored would blank the school's OpenAI key — the one
  /// field nothing in the app could put back. For the same reason the stored
  /// document is used as the base of the write rather than replaced by it, so
  /// a field this class does not model survives too. A doc that is not there
  /// yet is created with an empty key.
  ///
  /// **The role gate is the caller's.** Cosmos is reached with the app's
  /// single master key, so nothing on the server distinguishes a teacher from
  /// a student; the only call site is the teacher-only card in the Options
  /// page (`_GlobalModelCard`), gated on `isTeacherProvider`.
  Future<void> setModel(String model) async {
    await safeCosmos(() async {
      final stored = await _container.read(_docId, partitionKey: _pk);
      final next = GlobalConfig(
        model: model,
        apiKey: GlobalConfig.fromMap(stored ?? const {}).apiKey,
      );
      final base = Map<String, dynamic>.from(stored ?? const {})
        // Cosmos owns `_rid`, `_etag`, `_ts`…; echoing them back is at best
        // ignored and at worst rejected.
        ..removeWhere((k, _) => k.startsWith('_'));
      final doc = <String, dynamic>{...base, ...next.toMap()};
      await _container.upsert(doc, partitionKey: _pk);
      // The poll would get here within `kCosmosPollInterval`; publishing now
      // means the teacher's own radio row moves on the next frame.
      state = next;
    });
  }

  Future<GlobalConfig?> _fetchOnce() async {
    final doc = await _container.read(_docId, partitionKey: _pk);
    if (doc == null) return null;
    return GlobalConfig.fromMap(doc);
  }
}

final globalConfigServiceProvider =
    NotifierProvider<GlobalConfigService, GlobalConfig?>(
      GlobalConfigService.new,
    );
