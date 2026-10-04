// What the student's subgoal bar shows in the session, per LO (#230,
// CONDUCTOR_POLICY §4.5).
//
// The bar is one segment per non-optional LO of the active subgoal, each
// empty, half or full. It is only the display: the belief, the tutor's
// choices, the cached `progress` doc (the Leerpad, the teacher's overview,
// the report) and the grade read none of it. The conductor computes the
// segments from the snapshots and the calibration it already has at every
// question and answer, holds them for the session, and publishes them in
// [subgoalLoDisplayProvider].

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One segment of the bar.
enum LoDisplayState {
  /// More than one right answer away from mastery.
  empty,

  /// One right answer away: a strong positive at the student's calibration
  /// would master the LO ([oneRightAnswerMasters]).
  half,

  /// Mastered — now, or once (`firstMasteredAt`) — or stuck (§4.4). Stuck
  /// looks the same to the student as the advance it allows does (§4.4,
  /// "student-side invisibility").
  full,
}

/// The segment an LO gets from its belief as it is now: [snap] is the
/// decayed `(α, β)`, [calibration] the student's level.
///
/// Full when the LO was ever mastered ([firstMasteredAt], the one-way
/// reading the grade uses, #168), is mastered now (§4.1) or is stuck
/// (§4.4); half when one right answer would master it; empty otherwise.
LoDisplayState loDisplayStateOf({
  required BeliefSnapshot snap,
  required DateTime? lastPositiveAtCalibratedAt,
  required DateTime? firstMasteredAt,
  required QuestionDifficulty calibration,
}) {
  if (firstMasteredAt != null) return LoDisplayState.full;
  if (lastPositiveAtCalibratedAt != null && meetsMasteryMeanAndEvidence(snap)) {
    return LoDisplayState.full;
  }
  if (isStuck(snap)) return LoDisplayState.full;
  if (oneRightAnswerMasters(snap: snap, calibration: calibration)) {
    return LoDisplayState.half;
  }
  return LoDisplayState.empty;
}

/// Whether one right answer would master an LO at [snap]: a
/// `(positive, strong)` at [calibration], with the home factor (× 1.0),
/// applied to [snap] with the cap (§3.4), meets conditions 1 and 2 of §4.1.
/// Condition 3 that answer meets itself: it is a positive at calibration.
///
/// From the prior that is never true — one strong positive at hard leaves
/// μ at 0.79 — and after one right answer on hard or medium it is.
bool oneRightAnswerMasters({
  required BeliefSnapshot snap,
  required QuestionDifficulty calibration,
}) {
  final deltas = signalDeltas(
    kind: LoSignalKind.positive,
    strength: LoSignalStrength.strong,
    difficulty: calibration,
    provenance: EvidenceProvenance.home,
  );
  final next = applyEvidence(
    alpha: snap.alpha,
    beta: snap.beta,
    alphaDelta: deltas.alphaDelta,
    betaDelta: deltas.betaDelta,
  );
  return meetsMasteryMeanAndEvidence(next);
}

/// The segment to show, given what it showed so far this session ([held],
/// `null` at the session's first reading) and what the belief says now
/// ([fresh]). A segment does not go back on what the student did not answer
/// themselves:
///
///   - full stays full;
///   - half becomes empty only when [askedAndNotRight]: this turn was a
///     question on the LO itself, or a follow-up on it, and its answer was
///     not right. A negative from the side — the grader's signal on this LO
///     from a question about another — leaves it half.
///
/// Anything else follows the belief.
LoDisplayState heldLoDisplayState({
  required LoDisplayState? held,
  required LoDisplayState fresh,
  required bool askedAndNotRight,
}) {
  if (held == LoDisplayState.full) return LoDisplayState.full;
  if (held == LoDisplayState.half &&
      fresh == LoDisplayState.empty &&
      !askedAndNotRight) {
    return LoDisplayState.half;
  }
  return fresh;
}

/// One LO's segment.
class LoDisplayEntry {
  const LoDisplayEntry({required this.loId, required this.state});

  final String loId;
  final LoDisplayState state;

  @override
  bool operator ==(Object other) =>
      other is LoDisplayEntry && other.loId == loId && other.state == state;

  @override
  int get hashCode => Object.hash(loId, state);

  @override
  String toString() => '$loId: ${state.name}';
}

/// The bar of one subgoal: a segment per non-optional LO, in authoring
/// order.
class SubgoalLoDisplay {
  const SubgoalLoDisplay({required this.subgoalId, required this.los});

  final String subgoalId;
  final List<LoDisplayEntry> los;

  int count(LoDisplayState state) => los.where((e) => e.state == state).length;

  int get fullCount => count(LoDisplayState.full);
  int get halfCount => count(LoDisplayState.half);
  int get emptyCount => count(LoDisplayState.empty);

  /// The share of the bar filled: a full segment counts 1, a half one ½.
  double get fraction =>
      los.isEmpty ? 0.0 : (fullCount + 0.5 * halfCount) / los.length;

  @override
  bool operator ==(Object other) =>
      other is SubgoalLoDisplay &&
      other.subgoalId == subgoalId &&
      const ListEquality<LoDisplayEntry>().equals(other.los, los);

  @override
  int get hashCode =>
      Object.hash(subgoalId, const ListEquality<LoDisplayEntry>().hash(los));

  @override
  String toString() => 'SubgoalLoDisplay($subgoalId, $los)';
}

/// The segments the conductor last published, for whichever subgoal was
/// active then. `null` until the first session start.
final subgoalLoDisplayProvider = StateProvider<SubgoalLoDisplay?>((_) => null);

/// [subgoalLoDisplayProvider] when it is about the active subgoal, else
/// `null`: right after a change of subgoal, before the conductor has
/// published the new one's, the bar falls back to the cached share rather
/// than show the old subgoal's segments.
final activeSubgoalLoDisplayProvider = Provider<SubgoalLoDisplay?>((ref) {
  final activeId = ref.watch(
    goalSelectionProvider.select((s) => s.activeChildGoal?.id),
  );
  final display = ref.watch(subgoalLoDisplayProvider);
  if (activeId == null || display == null) return null;
  return display.subgoalId == activeId ? display : null;
});
