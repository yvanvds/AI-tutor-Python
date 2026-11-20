// What the student's subgoal bar shows in the session, per LO (#230, #325,
// CONDUCTOR_POLICY §4.5).
//
// The bar is one segment per non-optional LO of the active subgoal. Each
// counts down the right answers the LO still needs to be mastered
// ([rightAnswersToGo]), fills along with that number ([loSegmentFill]),
// carries a mark of its own when the LO has the mastery stamp, and says why
// the number went up when it did ([LoDisplayRise]). It is only the display:
// the belief, the tutor's choices, the cached `progress` doc (the Leerpad,
// the teacher's overview, the report) and the grade read none of it. The
// conductor computes the segments from the beliefs and the level it would
// ask each LO at, at every question and answer, and publishes them in
// [subgoalLoDisplayProvider].

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most right answers [rightAnswersToGo] counts; it never gets there —
/// from the cap at easy it is about a dozen.
const int kMaxRightAnswersToGo = 50;

/// How many right answers an LO still needs to be mastered (§4.1): 0 when
/// it is mastered now ([isMastered] on [snap], its decayed belief, and
/// [belief], its doc — `null` when it has none).
///
/// Counted as the student would get them: each a `(positive, strong)` at
/// home (× 1.0, the lower bound), no multiple choice, applied as every
/// answer is — forgetting, then the cap (§3.4) — and counting as a right own
/// question (condition 4, #279). The first at [askedAt], the level the app
/// would ask the LO at now (a notch under [calibration] while a rule of
/// §2.3 drops it), every next one at [calibration]: a right answer releases
/// the notch drop. Condition 3 asks for one right answer at [calibration];
/// one at a lower level does not give it. A stamp ([everMasteredBelief])
/// waives condition 4, as it does in [isMastered].
///
/// One right answer away is what #230 showed as half.
int rightAnswersToGo({
  required BeliefSnapshot snap,
  required LoBelief? belief,
  required QuestionDifficulty calibration,
  QuestionDifficulty? askedAt,
}) {
  if (isMastered(snap, belief)) return 0;
  final stamped = belief != null && everMasteredBelief(belief);
  var right = belief?.ownQuestionsRight ?? 0;
  var rightNonMcq = belief?.ownQuestionsRightNonMcq ?? 0;
  var atCalibration = belief?.lastPositiveAtCalibratedAt != null;
  var level = askedAt ?? calibration;
  var s = snap;
  for (var k = 1; k < kMaxRightAnswersToGo; k++) {
    final d = signalDeltas(
      kind: LoSignalKind.positive,
      strength: LoSignalStrength.strong,
      difficulty: level,
      provenance: EvidenceProvenance.home,
    );
    s = applyEvidence(
      alpha: s.alpha,
      beta: s.beta,
      alphaDelta: d.alphaDelta,
      betaDelta: d.betaDelta,
    );
    if (level.index >= calibration.index) atCalibration = true;
    right += 1;
    rightNonMcq += 1;
    if (atCalibration &&
        meetsMasteryMeanAndEvidence(s) &&
        (stamped ||
            meetsOwnQuestionsCondition(
              ownQuestionsRight: right,
              ownQuestionsRightNonMcq: rightNonMcq,
            ))) {
      return k;
    }
    level = calibration;
  }
  return kMaxRightAnswersToGo;
}

/// How many right answers a new LO needs at [calibration], from the prior
/// ([rightAnswersToGo] without a doc): 2 on hard, 3 on medium, 8 on easy.
int newLoRightAnswersToGo(QuestionDifficulty calibration) => rightAnswersToGo(
  snap: const BeliefSnapshot(PolicyConstants.prior, PolicyConstants.prior),
  belief: null,
  calibration: calibration,
);

/// How much of a segment is filled at [toGo] right answers to go: the share
/// of the way a new LO has to go at the student's level ([newLoToGo],
/// [newLoRightAnswersToGo]) that is behind it. Full at 0, empty at [newLoToGo]
/// or more, so a new LO starts empty and every right answer fills a step.
/// On medium that is 67% at 1 and 33% at 2; on hard 50% at 1; on easy an
/// eighth per answer. The number itself is in the segment.
double loSegmentFill(int toGo, {required int newLoToGo}) {
  if (toGo <= 0) return 1.0;
  if (newLoToGo <= 0) return 0.0;
  return (1 - toGo / newLoToGo).clamp(0.0, 1.0);
}

/// Why a segment's number went up.
enum LoDisplayRise {
  /// A question on the LO itself — or a follow-up on it — was not answered
  /// right.
  notRight,

  /// The app asks the LO a level lower now: the student's level went down,
  /// or a rule of §2.3 asks it a notch lower. A right answer there weighs
  /// less.
  lowerLevel,

  /// A negative on the LO from a question about another one (§2.4).
  otherQuestion,
}

/// What one segment showed, and the levels it was counted at: what the next
/// reading compares with ([nextLoDisplayReading]).
class LoDisplayReading {
  const LoDisplayReading({
    required this.toGo,
    required this.askedAt,
    required this.calibration,
    this.rose,
  });

  final int toGo;
  final QuestionDifficulty askedAt;
  final QuestionDifficulty calibration;

  /// Why [toGo] went up, while it stays there.
  final LoDisplayRise? rose;
}

/// The segment's next reading, given the one before in this session
/// ([previous], `null` at the session's first) and what the belief says now
/// ([toGo], counted at [askedAt] and [calibration]).
///
/// The number follows the belief, both ways. It goes up for a reason:
/// [turnRise], what this turn did to the LO (a question on it not answered
/// right, a negative on it from another question), or else a lower level
/// than the reading before. Without one it does not go up: an answer that
/// is not wrong never sets the count back. Forgetting (§3.4) can do that
/// on its own — a light right answer (a weak signal, a follow-up, a pick)
/// adds less than it forgets of an LO with much evidence — as it could
/// take away mastery before the guard of #311; a strong right answer at
/// the level asked never does.
///
/// The reason stays while the number does; it goes when the number drops.
LoDisplayReading nextLoDisplayReading({
  required LoDisplayReading? previous,
  required int toGo,
  required QuestionDifficulty askedAt,
  required QuestionDifficulty calibration,
  LoDisplayRise? turnRise,
}) {
  if (previous == null || toGo < previous.toGo) {
    return LoDisplayReading(
      toGo: toGo,
      askedAt: askedAt,
      calibration: calibration,
    );
  }
  if (toGo == previous.toGo) {
    return LoDisplayReading(
      toGo: toGo,
      askedAt: askedAt,
      calibration: calibration,
      rose: previous.rose,
    );
  }
  final lower =
      askedAt.index < previous.askedAt.index ||
      calibration.index < previous.calibration.index;
  final rise = turnRise ?? (lower ? LoDisplayRise.lowerLevel : null);
  return LoDisplayReading(
    toGo: rise == null ? previous.toGo : toGo,
    askedAt: askedAt,
    calibration: calibration,
    rose: rise ?? previous.rose,
  );
}

/// One LO's segment.
class LoDisplayEntry {
  const LoDisplayEntry({
    required this.loId,
    required this.toGo,
    required this.newLoToGo,
    this.demonstrated = false,
    this.rose,
  });

  final String loId;

  /// Right answers the LO still needs ([rightAnswersToGo]); 0 is mastered.
  final int toGo;

  /// Right answers a new LO needs at the student's level
  /// ([newLoRightAnswersToGo]): where the fill starts.
  final int newLoToGo;

  /// The LO carries the mastery stamp (`firstMasteredAt`, the one the grade
  /// and the Leerpad read): its own mark, which stays when the fill drops.
  final bool demonstrated;

  /// Why [toGo] went up in this session, while it stays there.
  final LoDisplayRise? rose;

  bool get mastered => toGo <= 0;

  /// The share of the segment filled ([loSegmentFill]).
  double get fill => loSegmentFill(toGo, newLoToGo: newLoToGo);

  @override
  bool operator ==(Object other) =>
      other is LoDisplayEntry &&
      other.loId == loId &&
      other.toGo == toGo &&
      other.newLoToGo == newLoToGo &&
      other.demonstrated == demonstrated &&
      other.rose == rose;

  @override
  int get hashCode => Object.hash(loId, toGo, newLoToGo, demonstrated, rose);

  @override
  String toString() =>
      '$loId: $toGo${demonstrated ? ' ✓' : ''}'
      '${rose == null ? '' : ' (${rose!.name})'}';
}

/// The bar of one subgoal: a segment per non-optional LO, in authoring
/// order, and the LO of the question on screen ([currentLoId]; `null` when
/// that question is about another subgoal — a warm-up review or a recheck —
/// or before the first).
class SubgoalLoDisplay {
  const SubgoalLoDisplay({
    required this.subgoalId,
    required this.los,
    this.currentLoId,
  });

  final String subgoalId;
  final List<LoDisplayEntry> los;
  final String? currentLoId;

  /// Segments at 0 to go.
  int get masteredCount => los.where((e) => e.mastered).length;

  /// The right answers still to go over all segments.
  int get toGoTotal => los.fold(0, (sum, e) => sum + e.toGo);

  /// The share of the bar filled: the mean of the segments' fills. The 2px
  /// line at the top of the window shows it.
  double get fraction =>
      los.isEmpty ? 0.0 : los.fold(0.0, (sum, e) => sum + e.fill) / los.length;

  /// This bar with [loId] as the LO of the question on screen.
  SubgoalLoDisplay withCurrent(String? loId) =>
      SubgoalLoDisplay(subgoalId: subgoalId, los: los, currentLoId: loId);

  @override
  bool operator ==(Object other) =>
      other is SubgoalLoDisplay &&
      other.subgoalId == subgoalId &&
      other.currentLoId == currentLoId &&
      const ListEquality<LoDisplayEntry>().equals(other.los, los);

  @override
  int get hashCode => Object.hash(
    subgoalId,
    currentLoId,
    const ListEquality<LoDisplayEntry>().hash(los),
  );

  @override
  String toString() => 'SubgoalLoDisplay($subgoalId, $los, at $currentLoId)';
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
