// Reads/writes the `status_reports` Cosmos container. Composite doc id
// `${uid}_${goalId}` with partition key = uid.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'status_report.dart';

class ReportService {
  ReportService({
    CosmosContainer? container,
    required this._getUid,
    this._getCurrentChildGoalId,
  }) : _containerOverride = container;

  final CosmosContainer? _containerOverride;
  final String? Function() _getUid;
  final String? Function()? _getCurrentChildGoalId;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.statusReports();

  String get _uid {
    final uid = _getUid();
    if (uid == null) throw StateError('No authenticated user.');
    return uid;
  }

  Future<List<StatusReport>> getAll() {
    final uid = _uid;
    return safeCosmos(() => _fetchAll(uid));
  }

  Stream<List<StatusReport>> watchAll() {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAll(uid))),
    );
  }

  Future<StatusReport?> getByGoalId(String goalID) {
    final uid = _uid;
    return safeCosmos(() => _fetchOne(uid, goalID));
  }

  // ---- teacher-scoped reads ----------------------------------------------

  /// All status reports for one student (teacher-side). Same partition as
  /// the signed-in-user reads, but addressed by an explicit uid.
  Future<List<StatusReport>> getStatusReportsForUser(String uid) {
    return safeCosmos(() => _fetchAll(uid));
  }

  Stream<List<StatusReport>> watchStatusReportsForUser(String uid) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAll(uid))),
    );
  }

  Future<void> upsert(StatusReport p) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.upsert(p.toMap(uid: uid), partitionKey: uid),
    );
  }

  Future<void> delete(String goalID) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.delete(
        CosmosDocId.statusReport(uid, goalID),
        partitionKey: uid,
      ),
    );
  }

  /// Upsert a status report for the currently selected child goal.
  /// No-op if no child goal is selected.
  Future<void> updateForCurrentChildGoal(String newReport) async {
    final goalId = _getCurrentChildGoalId?.call();
    if (goalId == null) return;
    await upsert(StatusReport(goalID: goalId, statusReport: newReport));
  }

  /// Upsert a status report against an explicit subgoal id. Used by the
  /// post-mastery status flow, where the active child goal has already
  /// advanced by the time the AI response comes back.
  Future<void> updateForGoal(String goalID, String newReport) async {
    await upsert(StatusReport(goalID: goalID, statusReport: newReport));
  }

  Future<List<StatusReport>> _fetchAll(String uid) async {
    final docs = await _container.query(
      'SELECT * FROM c WHERE c.uid = @uid',
      parameters: {'@uid': uid},
      partitionKey: uid,
    );
    return docs.map(StatusReport.fromCosmos).toList();
  }

  Future<StatusReport?> _fetchOne(String uid, String goalID) async {
    final doc = await _container.read(
      CosmosDocId.statusReport(uid, goalID),
      partitionKey: uid,
    );
    if (doc == null) return null;
    return StatusReport.fromCosmos(doc);
  }
}

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(
    getUid: () => ref.read(authServiceProvider)?.oid,
    getCurrentChildGoalId: () =>
        ref.read(goalSelectionProvider).activeChildGoal?.id,
  );
});
