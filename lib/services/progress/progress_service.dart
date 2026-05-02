// Reads/writes the `progress` Cosmos container. Composite doc id
// `${uid}_${goalId}` with partition key = uid.
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
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

import 'progress.dart';
import 'progress_sample.dart';

class ProgressService {
  ProgressService({
    CosmosContainer? container,
    CosmosContainer? historyContainer,
  })  : _containerOverride = container,
        _historyContainerOverride = historyContainer;

  final CosmosContainer? _containerOverride;
  final CosmosContainer? _historyContainerOverride;

  final ValueNotifier<double> currentProgress = ValueNotifier(0.0);

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.progress();

  CosmosContainer get _historyContainer =>
      _historyContainerOverride ?? CosmosPaths.progressHistory();

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

  /// Upserts the `progress` doc. When [recordHistory] is true (the default)
  /// and the persisted `progress` value actually changed, also writes a
  /// `progress_history` sample tagged with [quality] and [isWarmUp]. Pass
  /// `recordHistory: false` for derived writes such as the root-goal
  /// recompute, where sampling would just duplicate the child trajectories.
  Future<void> upsert(
    Progress p, {
    AnswerQuality? quality,
    bool isWarmUp = false,
    bool recordHistory = true,
  }) async {
    final uid = _uid;

    Progress? previous;
    if (recordHistory) {
      try {
        previous = await safeCosmos(() => _fetchOne(uid, p.goalID));
      } catch (e) {
        // Pre-read for change detection is best-effort. If it fails we just
        // skip the history sample below — the main upsert is what matters.
        debugPrint('ProgressService: pre-read for history failed: $e');
      }
    }

    await safeCosmos(
      () => _container.upsert(p.toMap(uid: uid), partitionKey: uid),
    );

    if (!recordHistory) return;
    if (previous != null && previous.progress == p.progress) return;

    await _writeHistorySample(
      uid: uid,
      progress: p,
      quality: quality,
      isWarmUp: isWarmUp,
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

  /// Debug-only wipe: removes every `progress` and `progress_history` doc
  /// belonging to the signed-in user. Used by the debug dialog so a tester
  /// can re-run the conductor from a clean slate without manually clearing
  /// rows. Resets `currentProgress` to 0 so the UI reflects the wipe.
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
    currentProgress.value = 0.0;
  }

  // ---- teacher-scoped reads ----------------------------------------------

  /// Cross-partition read of every `progress` doc, grouped by uid. Used by
  /// the teacher accounts overview to derive per-student summary columns
  /// without issuing per-row queries. Master-key auth (per the existing
  /// security stance) is what makes this OK; do not call from
  /// student-scoped flows. The Progress model itself doesn't carry uid, so
  /// callers look up entries via `byUid[account.uid]`.
  Future<Map<String, List<Progress>>> getAllProgress() {
    return safeCosmos(_fetchAllCrossPartition);
  }

  Stream<Map<String, List<Progress>>> watchAllProgress() {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(_fetchAllCrossPartition)),
    );
  }

  /// Read all `progress` docs for one student (teacher-side). Same partition
  /// as the signed-in-user reads, but addressed by an explicit uid.
  Future<List<Progress>> getProgressForUser(String uid) {
    return safeCosmos(() => _fetchAll(uid));
  }

  Stream<List<Progress>> watchProgressForUser(String uid) {
    return safeCosmosStream(
      pollingStream(() => safeCosmos(() => _fetchAll(uid))),
    );
  }

  /// Read `progress_history` for one student, ordered by `at` ascending.
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

  // ---- progress_history reads --------------------------------------------

  /// Samples for one (uid, goalId), ordered by `at` ascending. [since] is
  /// inclusive; [limit] caps the row count from the start of the ordered
  /// window.
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

  /// Samples across all goals for the current student, ordered by `at`
  /// ascending.
  Future<List<ProgressSample>> getAllHistory({
    DateTime? since,
    int? limit,
  }) {
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
          () => _fetchHistory(
            uid,
            goalID: goalID,
            since: since,
            limit: limit,
          ),
        ),
      ),
    );
  }

  Stream<List<ProgressSample>> watchAllHistory({
    DateTime? since,
    int? limit,
  }) {
    final uid = _uid;
    return safeCosmosStream(
      pollingStream(
        () => safeCosmos(
          () => _fetchHistory(uid, since: since, limit: limit),
        ),
      ),
    );
  }

  // ---- internals ---------------------------------------------------------

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
    required bool isWarmUp,
  }) async {
    final sample = ProgressSample(
      goalID: progress.goalID,
      progress: progress.progress,
      difficulty: progress.difficulty,
      quality: quality,
      isWarmUp: isWarmUp,
      at: DateTime.now().toUtc(),
    );
    try {
      await _historyContainer.create(
        sample.toMap(uid: uid),
        partitionKey: uid,
      );
    } catch (e) {
      // History is best-effort. The user-visible upsert already succeeded,
      // and surfacing this would route auth-error users to the recovery
      // screen even though their progress write went through. Log and move
      // on; the next progress change writes a fresh sample.
      debugPrint('ProgressService: history sample write failed: $e');
    }
  }
}
