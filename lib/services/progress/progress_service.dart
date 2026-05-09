// Reads/writes the `progress` Cosmos container. Composite doc id
// `${uid}_${goalId}` with partition key = uid.
//
// Under the LO-belief redesign, the `progress` doc is a derived cache: its
// `progress: 0.0..1.0` value is recomputed from per-LO beliefs whenever any
// constituent belief changes. Source of truth for student state lives in
// `lo_beliefs` and `accounts/{uid}.calibration`.
//
// Also owns the `progress_history` time-series writes: every successful
// `upsert` that actually changes the persisted `progress` value emits one
// sample doc to `progress_history`. History writes are best-effort — a
// failure there logs and continues so the user-visible progress update
// still succeeds.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress.dart';
import 'progress_sample.dart';

class ProgressService {
  ProgressService({
    CosmosContainer? container,
    CosmosContainer? historyContainer,
    required String? Function() getUid,
    void Function(double)? updateCurrentProgress,
  })  : _containerOverride = container,
        _historyContainerOverride = historyContainer,
        _getUid = getUid,
        _updateCurrentProgress = updateCurrentProgress;

  final CosmosContainer? _containerOverride;
  final CosmosContainer? _historyContainerOverride;
  final String? Function() _getUid;
  final void Function(double)? _updateCurrentProgress;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.progress();

  CosmosContainer get _historyContainer =>
      _historyContainerOverride ?? CosmosPaths.progressHistory();

  String get _uid {
    final uid = _getUid();
    if (uid == null) throw StateError('No authenticated user.');
    return uid;
  }

  void setCurrentProgress(double value) => _updateCurrentProgress?.call(value);

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

  /// Upserts the `progress` doc. When [recordHistory] is true (the default)
  /// and the persisted `progress` value actually changed, also writes a
  /// `progress_history` sample tagged with [quality]. Pass
  /// `recordHistory: false` for derived writes such as the root-goal
  /// recompute, where sampling would just duplicate the child trajectories.
  Future<void> upsert(
    Progress p, {
    AnswerQuality? quality,
    bool recordHistory = true,
  }) async {
    final uid = _uid;

    Progress? previous;
    if (recordHistory) {
      try {
        previous = await safeCosmos(() => _fetchOne(uid, p.goalID));
      } catch (e) {
        debugPrint('ProgressService: pre-read for history failed: $e');
      }
    }

    await safeCosmos(
      () => _container.upsert(p.toMap(uid: uid), partitionKey: uid),
    );

    if (!recordHistory) return;
    if (previous != null && previous.progress == p.progress) return;

    await _writeHistorySample(uid: uid, progress: p, quality: quality);
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

  Future<void> deleteAllForCurrentUser() async {
    final uid = _uid;
    await safeCosmos(() async {
      final progressDocs = await _container.query(
        'SELECT c.id FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      for (final doc in progressDocs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        await _container.delete(id, partitionKey: uid);
      }
      final historyDocs = await _historyContainer.query(
        'SELECT c.id FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      for (final doc in historyDocs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        await _historyContainer.delete(id, partitionKey: uid);
      }
    });
    setCurrentProgress(0.0);
  }

  // ---- teacher-scoped reads -----------------------------------------------

  Future<Map<String, List<Progress>>> getAllProgress() {
    return safeCosmos(_fetchAllCrossPartition);
  }

  Stream<Map<String, List<Progress>>> watchAllProgress() {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchAllCrossPartition)),
    );
  }

  Future<List<Progress>> getProgressForUser(String uid) {
    return safeCosmos(() => _fetchAll(uid));
  }

  Stream<List<Progress>> watchProgressForUser(String uid) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAll(uid))),
    );
  }

  Future<List<ProgressSample>> getHistoryForUser(
    String uid, {
    DateTime? since,
    int? limit,
  }) {
    return safeCosmos(
      () => _fetchHistory(uid, since: since, limit: limit),
    );
  }

  Stream<List<ProgressSample>> watchHistoryForUser(
    String uid, {
    DateTime? since,
    int? limit,
  }) {
    return safeCosmosStream(
      pollingStream(
        () => safeCosmos(
          () => _fetchHistory(uid, since: since, limit: limit),
        ),
      ),
    );
  }

  Future<List<ProgressSample>> getHistoryByGoalId(
    String goalID, {
    DateTime? since,
    int? limit,
  }) {
    final uid = _uid;
    return safeCosmos(
      () => _fetchHistory(uid, goalID: goalID, since: since, limit: limit),
    );
  }

  Future<List<ProgressSample>> getAllHistory({DateTime? since, int? limit}) {
    final uid = _uid;
    return safeCosmos(
      () => _fetchHistory(uid, since: since, limit: limit),
    );
  }

  Stream<List<ProgressSample>> watchHistoryByGoalId(
    String goalID, {
    DateTime? since,
    int? limit,
  }) {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(
        () => safeCosmos(
          () => _fetchHistory(uid, goalID: goalID, since: since, limit: limit),
        ),
      ),
    );
  }

  Stream<List<ProgressSample>> watchAllHistory({DateTime? since, int? limit}) {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(
        () => safeCosmos(
          () => _fetchHistory(uid, since: since, limit: limit),
        ),
      ),
    );
  }

  // ---- internals ----------------------------------------------------------

  Future<List<Progress>> _fetchAll(String uid) async {
    final docs = await _container.query(
      'SELECT * FROM c WHERE c.uid = @uid',
      parameters: {'@uid': uid},
      partitionKey: uid,
    );
    return docs.map(Progress.fromCosmos).toList();
  }

  Future<Map<String, List<Progress>>> _fetchAllCrossPartition() async {
    final docs = await _container.query(
      'SELECT * FROM c',
      crossPartition: true,
    );
    final out = <String, List<Progress>>{};
    for (final doc in docs) {
      final uid = doc['uid'] as String?;
      if (uid == null || uid.isEmpty) continue;
      out.putIfAbsent(uid, () => <Progress>[]).add(Progress.fromCosmos(doc));
    }
    return out;
  }

  Future<Progress?> _fetchOne(String uid, String goalID) async {
    final doc = await _container.read(
      CosmosDocId.progress(uid, goalID),
      partitionKey: uid,
    );
    if (doc == null) return null;
    return Progress.fromCosmos(doc);
  }

  Future<List<ProgressSample>> _fetchHistory(
    String uid, {
    String? goalID,
    DateTime? since,
    int? limit,
  }) async {
    final clauses = <String>['c.uid = @uid'];
    final params = <String, Object?>{'@uid': uid};
    if (goalID != null) {
      clauses.add('c.goalId = @goalId');
      params['@goalId'] = goalID;
    }
    if (since != null) {
      clauses.add('c.at >= @since');
      params['@since'] = since.toUtc().toIso8601String();
    }
    final top = limit != null ? 'TOP $limit ' : '';
    final sql =
        'SELECT $top* FROM c WHERE ${clauses.join(' AND ')} ORDER BY c.at ASC';
    final docs = await _historyContainer.query(
      sql,
      parameters: params,
      partitionKey: uid,
    );
    return docs.map(ProgressSample.fromCosmos).toList();
  }

  Future<void> _writeHistorySample({
    required String uid,
    required Progress progress,
    required AnswerQuality? quality,
  }) async {
    final sample = ProgressSample(
      goalID: progress.goalID,
      progress: progress.progress,
      quality: quality,
      at: DateTime.now().toUtc(),
    );
    try {
      await _historyContainer.create(
        sample.toMap(uid: uid),
        partitionKey: uid,
      );
    } catch (e) {
      debugPrint('ProgressService: history sample write failed: $e');
    }
  }
}

final currentProgressProvider = StateProvider<double>((_) => 0.0);

final progressServiceProvider = Provider<ProgressService>((ref) {
  return ProgressService(
    getUid: () => ref.read(authServiceProvider)?.oid,
    updateCurrentProgress: (v) =>
        ref.read(currentProgressProvider.notifier).state = v,
  );
});
