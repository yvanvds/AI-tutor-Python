// Reads / writes the `lo_beliefs` Cosmos container. One doc per
// `(uid, subgoalId, loId)`; partition key `uid`. The conductor goes through
// this service for every belief lookup and update so the on-disk schema is
// hidden from the algorithm code.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoBeliefsService {
  LoBeliefsService({
    CosmosContainer? container,
    required String? Function() getUid,
  })  : _containerOverride = container,
        _getUid = getUid;

  final CosmosContainer? _containerOverride;
  final String? Function() _getUid;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.loBeliefs();

  String get _uid {
    final uid = _getUid();
    if (uid == null) throw StateError('No authenticated user.');
    return uid;
  }

  Future<List<LoBelief>> getAllForSubgoal(String subgoalId) {
    final uid = _uid;
    return safeCosmos(() async {
      final docs = await _container.query(
        'SELECT * FROM c WHERE c.uid = @uid AND c.subgoalId = @sid',
        parameters: {'@uid': uid, '@sid': subgoalId},
        partitionKey: uid,
      );
      return docs.map(LoBelief.fromCosmos).toList();
    });
  }

  Future<LoBelief?> getOne({
    required String subgoalId,
    required String loId,
  }) {
    final uid = _uid;
    return safeCosmos(() async {
      final doc = await _container.read(
        LoBelief.docIdFor(uid: uid, subgoalId: subgoalId, loId: loId),
        partitionKey: uid,
      );
      if (doc == null) return null;
      return LoBelief.fromCosmos(doc);
    });
  }

  Future<void> upsert(LoBelief belief) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.upsert(belief.toMap(uid: uid), partitionKey: uid),
    );
  }

  Future<void> deleteAllForCurrentUser() async {
    final uid = _uid;
    await safeCosmos(() async {
      final docs = await _container.query(
        'SELECT c.id FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      for (final doc in docs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        await _container.delete(id, partitionKey: uid);
      }
    });
  }
}

final loBeliefsServiceProvider = Provider<LoBeliefsService>((ref) {
  return LoBeliefsService(
    getUid: () => ref.read(authServiceProvider)?.oid,
  );
});
