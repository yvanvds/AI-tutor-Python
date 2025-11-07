import 'dart:async';

import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'global_config.dart';

class GlobalConfigService {
  GlobalConfigService() {
    // Start watching immediately and keep ValueNotifier in sync
    _subscription = watchConfig().listen((cfg) {
      config.value = cfg;
    });
  }

  final LocalApiKeyStorage localStorage = LocalApiKeyStorage();

  final DocumentReference _globalConfigDoc = FirebaseFirestore.instance
      .collection('config')
      .doc('global');

  /// Exposed latest config (null until first load or if doc missing).
  final ValueNotifier<GlobalConfig?> config = ValueNotifier<GlobalConfig?>(
    null,
  );

  late final StreamSubscription<GlobalConfig?> _subscription;

  /// Typed reference to the single config document.
  DocumentReference<GlobalConfig> _docRef() {
    return _globalConfigDoc.withConverter<GlobalConfig>(
      fromFirestore: (snap, _) => GlobalConfig.fromDoc(snap),
      toFirestore: (cfg, _) => cfg.toMap(),
    );
  }

  /// Read once.
  Future<GlobalConfig?> getConfig() async {
    final snap = await safeFirestore(() => _docRef().get());
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Listen for live updates.
  Stream<GlobalConfig?> watchConfig() {
    return safeFirestoreStream(
      _docRef().snapshots().map((snap) => snap.data()),
    );
  }

  /// Call when you're done with this service (e.g. on app shutdown).
  void dispose() {
    _subscription.cancel();
    config.dispose();
  }
}
