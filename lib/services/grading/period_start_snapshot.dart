// One row of the `period_start_snapshots` Cosmos container (#110): what the
// grade formula would have read per learning objective at the start of a
// milestone's grading period — `mastered` under the three conditions of
// CONDUCTOR_POLICY §4.1 and the `highestPositiveDifficulty` ratchet — so
// `M_start` (PUNTENFORMULE §2.4) is the same §2.3 arithmetic as `M_end`
// instead of the per-subgoal estimate from `progress_history`.
//
// Doc id `${uid}_${milestoneId}`, partition key `/uid`. Written by the
// student app on its first session after `periodStart`
// (`PeriodStartSnapshotService.ensureForCurrentUser`), read teacher-side by
// `GradeProposalService.compute`.
//
// Why the snapshot can be *exact* although it is written days after the
// period started: a belief is stored as `(α, β, lastUpdatedAt)` and decay is
// applied lazily on read, so its state at any instant after `lastUpdatedAt`
// is a pure function of the doc. A belief not written since `periodStart`
// is therefore read *as of `periodStart`*, not as of the session. Only a
// belief already written inside the period (a milestone defined after the
// student worked, or a session on a machine that lost the write) has lost
// its period-start state; it is read as of the snapshot moment and flagged
// `exact: false` so the proposal can say how many of its LOs that concerns.

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';

import 'grade_formula.dart';
import 'milestone.dart';

/// One learning objective as of the period start.
class SnapshotLo {
  const SnapshotLo({
    required this.subgoalId,
    required this.loId,
    required this.mastered,
    required this.highest,
    required this.exact,
  });

  final String subgoalId;
  final String loId;
  final bool mastered;
  final QuestionDifficulty? highest;

  /// Whether the belief was still untouched since `periodStart` when the
  /// snapshot was taken, i.e. whether [mastered] and [highest] are the
  /// period-start values rather than the snapshot-moment ones.
  final bool exact;

  String get key => Milestone.loKey(subgoalId, loId);

  LoGradeInput get input => LoGradeInput(mastered: mastered, highest: highest);

  Map<String, dynamic> toMap() => {
    'subgoalId': subgoalId,
    'loId': loId,
    'mastered': mastered,
    if (highest != null) 'highest': highest!.name,
    'exact': exact,
  };

  factory SnapshotLo.fromMap(Map<String, dynamic> m) {
    final highestRaw = m['highest'];
    return SnapshotLo(
      subgoalId: (m['subgoalId'] as String?) ?? '',
      loId: (m['loId'] as String?) ?? '',
      mastered: m['mastered'] == true,
      highest: QuestionDifficulty.values.cast<QuestionDifficulty?>().firstWhere(
        (d) => d!.name == highestRaw,
        orElse: () => null,
      ),
      exact: m['exact'] != false,
    );
  }
}

class PeriodStartSnapshot {
  const PeriodStartSnapshot({
    required this.uid,
    required this.milestoneId,
    required this.periodStart,
    required this.takenAt,
    required this.los,
  });

  final String uid;
  final String milestoneId;

  /// The milestone's `periodStart` this snapshot was taken for. A milestone
  /// whose period start was moved afterwards no longer matches, and the
  /// student app takes a fresh one.
  final DateTime periodStart;
  final DateTime takenAt;

  /// Every belief the student had, not only the milestone's LOs of the
  /// moment: a subgoal the teacher adds to the milestone later still finds
  /// its period-start state here. An LO without an entry had no belief doc
  /// at the period start — never probed, not mastered.
  final List<SnapshotLo> los;

  /// Whether every entry is a period-start reading.
  bool get exact => los.every((e) => e.exact);

  /// Matches [milestone] when it was taken for the same period start.
  bool isFor(Milestone milestone) =>
      milestoneId == milestone.id &&
      periodStart.isAtSameMomentAs(milestone.periodStart);

  /// The formula's per-LO inputs (§2.2), keyed by `Milestone.loKey`.
  Map<String, LoGradeInput> get inputs => {for (final e in los) e.key: e.input};

  /// Of [milestoneLos], how many were read late (`exact: false`).
  int inexactCountFor(List<MilestoneLo> milestoneLos) {
    final inexact = {
      for (final e in los)
        if (!e.exact) e.key,
    };
    return milestoneLos.where((lo) => inexact.contains(lo.key)).length;
  }

  /// Reads [beliefs] as of [milestone]'s period start. A belief last
  /// written at or before `periodStart` is decayed to exactly that instant;
  /// one already written inside the period is read as of [now] and flagged.
  factory PeriodStartSnapshot.build({
    required String uid,
    required Milestone milestone,
    required List<LoBelief> beliefs,
    required DateTime now,
  }) {
    final periodStart = milestone.periodStart;
    final entries = <SnapshotLo>[];
    for (final b in beliefs) {
      final exact = !b.lastUpdatedAt.isAfter(periodStart);
      final input = LoGradeInput.fromBelief(b, now: exact ? periodStart : now);
      entries.add(
        SnapshotLo(
          subgoalId: b.subgoalId,
          loId: b.loId,
          mastered: input.mastered,
          highest: input.highest,
          exact: exact,
        ),
      );
    }
    entries.sort((a, b) => a.key.compareTo(b.key));
    return PeriodStartSnapshot(
      uid: uid,
      milestoneId: milestone.id,
      periodStart: periodStart,
      takenAt: now,
      los: entries,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': CosmosDocId.periodStartSnapshot(uid, milestoneId),
    'type': 'period_start_snapshot',
    'uid': uid,
    'milestoneId': milestoneId,
    'periodStart': periodStart.toUtc().toIso8601String(),
    'takenAt': takenAt.toUtc().toIso8601String(),
    'los': [for (final e in los) e.toMap()],
  };

  factory PeriodStartSnapshot.fromCosmos(Map<String, dynamic> doc) {
    DateTime parseDate(Object? raw) => raw is String
        ? (DateTime.tryParse(raw) ?? DateTime.utc(1970))
        : DateTime.utc(1970);
    return PeriodStartSnapshot(
      uid: (doc['uid'] as String?) ?? '',
      milestoneId: (doc['milestoneId'] as String?) ?? '',
      periodStart: parseDate(doc['periodStart']),
      takenAt: parseDate(doc['takenAt']),
      los: [
        for (final e in (doc['los'] as List?) ?? const [])
          if (e is Map) SnapshotLo.fromMap(Map<String, dynamic>.from(e)),
      ],
    );
  }
}
