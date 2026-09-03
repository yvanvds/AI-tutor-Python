// Reads / writes the `period_start_snapshots` Cosmos container (#110).
//
// Two callers, two sides of the app:
//   - the student app calls [ensureForCurrentUser] at session start, before
//     any belief of the session is written, and it freezes the period start
//     of every milestone whose `periodStart` has passed and has no snapshot
//     yet (or whose snapshot was taken for another `periodStart`);
//   - the teacher's `GradeProposalService.compute` calls [getStored] with an
//     explicit uid to read `M_start` from it.
//
// The conductor knows nothing of this: the tutor session runs it once,
// best-effort, and a failure only means the next session tries again.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'milestone_service.dart';
import 'period_start_snapshot.dart';

class PeriodStartSnapshotService {
  PeriodStartSnapshotService({
    CosmosContainer? container,
    required MilestoneService milestones,
    required LoBeliefsService beliefs,
    required String? Function() getUid,
    DateTime Function()? now,
  }) : this._(container, milestones, beliefs, getUid, now ?? _utcNow);

  PeriodStartSnapshotService._(
    this._containerOverride,
    this._milestones,
    this._beliefs,
    this._getUid,
    this._now,
  );

  static DateTime _utcNow() => DateTime.now().toUtc();

  final CosmosContainer? _containerOverride;
  final MilestoneService _milestones;
  final LoBeliefsService _beliefs;
  final String? Function() _getUid;
  final DateTime Function() _now;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.periodStartSnapshots();

  String get _uid {
    final uid = _getUid();
    if (uid == null) throw StateError('No authenticated user.');
    return uid;
  }

  /// The snapshot of [uid] for [milestoneId], teacher-side read.
  Future<PeriodStartSnapshot?> getStored(String uid, String milestoneId) =>
      safeCosmos(() async {
        final doc = await _container.read(
          CosmosDocId.periodStartSnapshot(uid, milestoneId),
          partitionKey: uid,
        );
        return doc == null ? null : PeriodStartSnapshot.fromCosmos(doc);
      });

  /// Freezes the period start of every milestone that needs it for the
  /// signed-in student. Returns the number of snapshots written; 0 is the
  /// normal case after the first session of a period.
  ///
  /// Must run before the session writes any belief: the beliefs are read
  /// as of `periodStart` for as long as nothing has touched them since
  /// (see `period_start_snapshot.dart`).
  Future<int> ensureForCurrentUser() async {
    final uid = _uid;
    final now = _now();
    final milestones = await _milestones.getAllOnce();
    final started = [
      for (final m in milestones)
        if (!m.periodStart.isAfter(now)) m,
    ];
    if (started.isEmpty) return 0;

    final existing = await safeCosmos(() async {
      final docs = await _container.query(
        'SELECT * FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      return {
        for (final s in docs.map(PeriodStartSnapshot.fromCosmos))
          s.milestoneId: s,
      };
    });
    final missing = [
      for (final m in started)
        if (!(existing[m.id]?.isFor(m) ?? false)) m,
    ];
    if (missing.isEmpty) return 0;

    final beliefs = await _beliefs.getAllForCurrentUser();
    for (final m in missing) {
      final snapshot = PeriodStartSnapshot.build(
        uid: uid,
        milestone: m,
        beliefs: beliefs,
        now: now,
      );
      await safeCosmos(
        () => _container.upsert(snapshot.toMap(), partitionKey: uid),
      );
    }
    return missing.length;
  }
}

final periodStartSnapshotServiceProvider = Provider<PeriodStartSnapshotService>(
  (ref) => PeriodStartSnapshotService(
    milestones: ref.read(milestoneServiceProvider),
    beliefs: ref.read(loBeliefsServiceProvider),
    getUid: () => ref.read(authServiceProvider)?.oid,
  ),
);
