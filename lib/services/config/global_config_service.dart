import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter/material.dart';

import 'global_config.dart';

class GlobalConfigService {
  GlobalConfigService() {
    _subscription = watchConfig().listen((cfg) {
      config.value = cfg;
    });
  }

  final LocalApiKeyStorage localStorage = LocalApiKeyStorage();

  static const String _pk = CosmosPartitions.config;
  static const String _docId = CosmosDocId.globalConfig;

  CosmosContainer get _container => CosmosPaths.config();

  /// Exposed latest config (null until first load or if doc missing).
  final ValueNotifier<GlobalConfig?> config = ValueNotifier<GlobalConfig?>(
    null,
  );

  late final StreamSubscription<GlobalConfig?> _subscription;

  Future<GlobalConfig?> getConfig() => safeCosmos(_fetchOnce);

  /// Latest config from the polling watcher, or null if not yet fetched.
  /// Synchronous fast-path for hot callers (e.g. the AI request loop) that
  /// must not block on a Cosmos round-trip every call.
  GlobalConfig? get cachedConfig => config.value;

  Stream<GlobalConfig?> watchConfig() {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchOnce)),
    );
  }

  void dispose() {
    _subscription.cancel();
    config.dispose();
  }

  Future<GlobalConfig?> _fetchOnce() async {
    final doc = await _container.read(_docId, partitionKey: _pk);
    if (doc == null) return null;
    return GlobalConfig.fromMap(doc);
  }
}
