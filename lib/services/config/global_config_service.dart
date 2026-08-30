import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'global_config.dart';

class GlobalConfigService extends Notifier<GlobalConfig?> {
  static const String _pk = CosmosPartitions.config;
  static const String _docId = CosmosDocId.globalConfig;

  CosmosContainer get _container => CosmosPaths.config();

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
