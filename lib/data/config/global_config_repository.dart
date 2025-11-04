import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'global_config.dart';

class GlobalConfigRepository {
  final DocumentReference _globalConfigDoc = FirebaseFirestore.instance
      .collection('config')
      .doc('global');

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
}
