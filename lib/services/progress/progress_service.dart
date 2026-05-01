// Cosmos-backed ProgressService (Step 3 of the migration).
//
// Doc-id change vs Firestore: the old subcollection
// `accounts/{uid}/progress/{goalId}` becomes a flat `progress` container
// with composite doc id `${uid}_${goalId}` and partition key = uid.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

import 'progress.dart';

class ProgressService {
  ProgressService();

  final ValueNotifier<double> currentProgress = ValueNotifier(0.0);

  CosmosContainer get _container => CosmosPaths.progress();

  String get _uid {
    final uid = DataService.auth.currentUser.value?.oid;
    if (uid == null) {
      throw StateError('No authenticated user.');
    }
    return uid;
  }

  Future<List<Progress>> getAll() {
    final uid = _uid;
    return safeCosmos(() => _fetchAll(uid));
  }

  Stream<List<Progress>> watchAll() {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAll(uid))),
    );
  }

  Future<Progress?> getByGoalId(String goalID) {
    final uid = _uid;
    return safeCosmos(() => _fetchOne(uid, goalID));
  }

  Stream<Progress?> streamByGoalId(String goalID) {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchOne(uid, goalID))),
    );
  }

  Future<void> upsert(Progress p) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.upsert(p.toMap(uid: uid), partitionKey: uid),
    );
  }

  Future<void> delete(String goalID) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.delete(
        CosmosDocId.progress(uid, goalID),
        partitionKey: uid,
      ),
    );
  }

  Future<List<Progress>> _fetchAll(String uid) async {
    final docs = await _container.query(
      'SELECT * FROM c WHERE c.uid = @uid',
      parameters: {'@uid': uid},
      partitionKey: uid,
    );
    return docs.map(Progress.fromCosmos).toList();
  }

  Future<Progress?> _fetchOne(String uid, String goalID) async {
    final doc = await _container.read(
      CosmosDocId.progress(uid, goalID),
      partitionKey: uid,
    );
    if (doc == null) return null;
    return Progress.fromCosmos(doc);
  }
}
