// Pure arithmetic primitives for the per-LO Beta belief.
//
// The conductor delegates every (α, β) calculation to this module so the
// arithmetic can be unit-tested in isolation, replayed at different
// constants in the future, and audited against `docs/CONDUCTOR_POLICY.md`
// §3–§4 line-by-line.

import 'dart:math' as math;

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';

class BeliefSnapshot {
  final double alpha;
  final double beta;
  const BeliefSnapshot(this.alpha, this.beta);

  double get evidence => alpha + beta;
  double get mean => evidence == 0 ? 0.5 : alpha / evidence;
}

/// Decay applied lazily on read. Half-life: `PolicyConstants.decayHalfLife`.
/// Preserves the prior so an untouched LO drifts to (1, 1), not (0, 0).
BeliefSnapshot applyDecay({
  required double alpha,
  required double beta,
  required DateTime lastUpdatedAt,
  required DateTime now,
}) {
  final elapsed = now.difference(lastUpdatedAt);
  if (elapsed <= Duration.zero) {
    return BeliefSnapshot(alpha, beta);
  }
  final halfLifeDays =
      PolicyConstants.decayHalfLife.inMicroseconds /
      Duration.microsecondsPerDay;
  final elapsedDays = elapsed.inMicroseconds / Duration.microsecondsPerDay;
  final d = math.pow(0.5, elapsedDays / halfLifeDays).toDouble();
  final aEff = PolicyConstants.prior + (alpha - PolicyConstants.prior) * d;
  final bEff = PolicyConstants.prior + (beta - PolicyConstants.prior) * d;
  return BeliefSnapshot(aEff, bEff);
}

enum LoSignalKind { positive, negative, neutral }

enum LoSignalStrength { strong, moderate, weak }

double baseWeight(LoSignalStrength s) {
  switch (s) {
    case LoSignalStrength.strong:
      return PolicyConstants.weightStrong;
    case LoSignalStrength.moderate:
      return PolicyConstants.weightModerate;
    case LoSignalStrength.weak:
      return PolicyConstants.weightWeak;
  }
}

/// Compute the (αDelta, βDelta) increments for a single signal at a given
/// difficulty and provenance. `neutral` returns (0, 0).
///
/// [difficulty] picks the positive or the negative multiplier by [kind]
/// (#169, CONDUCTOR_POLICY §3.2, PUNTENFORMULE §1.2): a positive at hard
/// weighs more than one at easy, a negative at hard weighs *less* — so the
/// mean reads the level the question was asked at.
///
/// [provenance] applies the supervised weight factor `s`
/// (CONDUCTOR_POLICY §3.2, PUNTENFORMULE §2.7): symmetric in positive and
/// negative, unlike the difficulty multiplier, so it changes how *hard* a
/// piece of evidence is, not which way it points.
///
/// [multipleChoice] is a signal of a multiple-choice question (#279, not a
/// follow-up on one): a positive weighs
/// `PolicyConstants.multipleChoicePositiveFactor` — a right pick is half
/// the evidence a right answer the student wrote is — and a negative as
/// any other.
({double alphaDelta, double betaDelta}) signalDeltas({
  required LoSignalKind kind,
  required LoSignalStrength strength,
  required QuestionDifficulty difficulty,
  EvidenceProvenance provenance = EvidenceProvenance.home,
  bool multipleChoice = false,
}) {
  if (kind == LoSignalKind.neutral) {
    return (alphaDelta: 0.0, betaDelta: 0.0);
  }
  final difficultyFactor = kind == LoSignalKind.positive
      ? PolicyConstants.positiveDifficultyMultiplier(difficulty)
      : PolicyConstants.negativeDifficultyMultiplier(difficulty);
  final pickFactor = multipleChoice && kind == LoSignalKind.positive
      ? PolicyConstants.multipleChoicePositiveFactor
      : 1.0;
  final weighted =
      baseWeight(strength) *
      difficultyFactor *
      pickFactor *
      PolicyConstants.provenanceMultiplier(provenance);
  if (kind == LoSignalKind.positive) {
    return (alphaDelta: weighted, betaDelta: 0.0);
  }
  return (alphaDelta: 0.0, betaDelta: weighted);
}

/// Transfer credit (#101, CONDUCTOR_POLICY §3.7, PUNTENFORMULE §2.8): the
/// small positive an already-mastered LO earns when a *working* solution
/// to a later exercise correctly uses it. Deliberately not a parallel
/// weight path: it is an ordinary `(positive, weak)` signal treated as
/// `medium` — the same footing as a follow-up signal (§6.2) — so it is
/// `weightWeak × 1.0 × s`, with `s` the provenance multiplier. Small by
/// construction (≤ the weak weight), and the Beta arithmetic gives the
/// diminishing returns for free.
({double alphaDelta, double betaDelta}) transferCreditDeltas({
  EvidenceProvenance provenance = EvidenceProvenance.home,
}) => signalDeltas(
  kind: LoSignalKind.positive,
  strength: LoSignalStrength.weak,
  difficulty: QuestionDifficulty.medium,
  provenance: provenance,
);

/// Incidental *positive* signal on an LO of an *earlier* subgoal (#108,
/// CONDUCTOR_POLICY §2.4): the grader saw the answer show that an LO
/// outside the active subgoal is solid. It is ordinary evidence in the
/// grader's own [strength], but the probe's difficulty was set for the
/// target LO, not this one, so it is treated as `medium` — the same footing
/// as a follow-up signal (§6.2) and a transfer credit (§3.7). Provenance
/// applies as everywhere.
///
/// A cross-subgoal *negative* never reaches the belief (#167): it is the
/// least reliable verdict the system has and lands on LOs the tutor no
/// longer probes directly, so a debit here would never be re-tested. The
/// conductor turns it into a review flag instead ([nextRegressedAt]) and
/// does not call this for it. Nor for a cross-subgoal *neutral* (#204):
/// that one is only logged — no doc, no clock.
///
/// A positive from a multiple-choice question weighs half here too
/// ([multipleChoice], #279): the factor is the turn's, not the target's.
({double alphaDelta, double betaDelta}) crossSubgoalSignalDeltas({
  required LoSignalKind kind,
  required LoSignalStrength strength,
  EvidenceProvenance provenance = EvidenceProvenance.home,
  bool multipleChoice = false,
}) => signalDeltas(
  kind: kind,
  strength: strength,
  difficulty: QuestionDifficulty.medium,
  provenance: provenance,
  multipleChoice: multipleChoice,
);

/// Whether an LO has ever met all the mastery conditions — the gate for
/// transfer credit (CONDUCTOR_POLICY §3.7): an LO never mastered by direct
/// probing cannot be brought to mastery sideways.
///
/// [firstMasteredAt] is the persisted one-way stamp. Docs written before
/// it existed fall back to "mastered as of the last direct write": the
/// stored `(α, β)` are post-update values, so if they meet the mean and
/// evidence conditions and the calibrated-positive ratchet is set, the LO
/// was mastered the last time it was probed. Decay since then does not
/// matter — that is exactly the gap transfer credit is meant to close.
/// The evidence bar is today's (`masteryEvidenceMin`, #276), not the 4 an
/// old build wrote under: the conductor applies this reading to every doc
/// without a stamp, so the old bar would stamp a new doc between 4 and
/// 5.75. Condition 4 (#279) is today's for the same reason on a doc that
/// keeps the right own questions: formula 1.1 wrote it, and a doc that
/// met conditions 1–3 without them has no stamp and must not get one at
/// its next write. A doc without the counts is from before 1.1, and this
/// reading recognises a stamp the rules of its day gave and an old build
/// did not write — a stamp that is there stays (#168), so condition 4 is
/// not asked of it.
bool everMastered({
  required DateTime? firstMasteredAt,
  required double alpha,
  required double beta,
  required DateTime? lastPositiveAtCalibratedAt,
  required int? ownQuestionsRight,
  required int? ownQuestionsRightNonMcq,
}) {
  if (firstMasteredAt != null) return true;
  if (lastPositiveAtCalibratedAt == null ||
      !meetsMasteryMeanAndEvidence(BeliefSnapshot(alpha, beta))) {
    return false;
  }
  final countsKept =
      ownQuestionsRight != null || ownQuestionsRightNonMcq != null;
  return !countsKept ||
      meetsOwnQuestionsCondition(
        ownQuestionsRight: ownQuestionsRight,
        ownQuestionsRightNonMcq: ownQuestionsRightNonMcq,
      );
}

/// [everMastered] of a stored doc.
bool everMasteredBelief(LoBelief b) => everMastered(
  firstMasteredAt: b.firstMasteredAt,
  alpha: b.alpha,
  beta: b.beta,
  lastPositiveAtCalibratedAt: b.lastPositiveAtCalibratedAt,
  ownQuestionsRight: b.ownQuestionsRight,
  ownQuestionsRightNonMcq: b.ownQuestionsRightNonMcq,
);

/// The warm-up review flag after a graded turn touched an LO outside the
/// active subgoal (#112, #167; CONDUCTOR_POLICY §1.5, §2.4): the value of
/// `regressedAt` to persist, given [current] and what this turn did.
///
/// The flag means "a direct re-probe is owed". It says nothing about the
/// belief, which since #167 an incidental negative no longer touches:
///
///   - a [directProbe] of the LO (a warm-up review, or any probe while its
///     subgoal is active — follow-up grading included) clears it whichever
///     way the answer went: the review has happened and the ordinary
///     staleness clock takes over;
///   - an incidental cross-subgoal [negative] (§2.4) sets it — kept if
///     already set, so the oldest open question is reviewed first. The
///     negative is not evidence, it is the reason to ask; the flag is all
///     it leaves behind;
///   - any other indirect write — a transfer credit (§3.7), a positive
///     incidental — leaves it as it was. Good news from the side does not
///     answer the question the negative raised; the review does.
///
/// Only an LO that [everMastered] carries the flag: one the student never
/// had is not review material (§1.5), so anything else reads `null`.
DateTime? nextRegressedAt({
  required DateTime? current,
  required bool directProbe,
  required bool everMastered,
  required bool negative,
  required DateTime now,
}) {
  if (directProbe || !everMastered) return null;
  if (negative) return current ?? now;
  return current;
}

/// Apply an evidence delta (CONDUCTOR_POLICY 3.4): forget, then
/// cap-then-add.
///
/// Forgetting per answer (#278, formula 1.1): the evidence above the prior
/// shrinks by `PolicyConstants.forgetFactor` before the new evidence is
/// added, on every write that carries weight — the question's signal, a
/// follow-up, a side signal, a transfer credit. A zero delta (a neutral)
/// shrinks nothing.
///
/// Then the cap, a backstop since #278: when the resulting `α + β` would
/// exceed `PolicyConstants.evidenceCap`, existing evidence-above-prior is
/// shrunk proportionally to make room.
BeliefSnapshot applyEvidence({
  required double alpha,
  required double beta,
  required double alphaDelta,
  required double betaDelta,
}) {
  if (alphaDelta == 0 && betaDelta == 0) {
    return BeliefSnapshot(alpha, beta);
  }
  final forgotten = forgetBeforeEvidence(BeliefSnapshot(alpha, beta));
  alpha = forgotten.alpha;
  beta = forgotten.beta;
  final cap = PolicyConstants.evidenceCap;
  final priorMass = 2 * PolicyConstants.prior;
  final newDelta = alphaDelta + betaDelta;
  if (alpha + beta + newDelta > cap) {
    final excessCapacity = cap - priorMass - newDelta;
    final existingExcess = alpha + beta - priorMass;
    if (existingExcess > 0 && excessCapacity > 0) {
      final scale = excessCapacity / existingExcess;
      alpha = PolicyConstants.prior + (alpha - PolicyConstants.prior) * scale;
      beta = PolicyConstants.prior + (beta - PolicyConstants.prior) * scale;
    } else if (excessCapacity <= 0) {
      // The new evidence alone exceeds capacity-for-non-prior. Collapse to
      // pure prior + new — no room for any of the existing excess.
      alpha = PolicyConstants.prior;
      beta = PolicyConstants.prior;
    }
  }
  return BeliefSnapshot(alpha + alphaDelta, beta + betaDelta);
}

/// The forgetting step of [applyEvidence] (#278): what [snap] holds above
/// the prior, shrunk by `PolicyConstants.forgetFactor`. The prior itself
/// stays, so an LO at `(1, 1)` is unchanged and the first answer lands in
/// full; the mean moves toward one half, as with decay (§3.3), but per
/// answer instead of per day.
BeliefSnapshot forgetBeforeEvidence(BeliefSnapshot snap) {
  const prior = PolicyConstants.prior;
  const lambda = PolicyConstants.forgetFactor;
  return BeliefSnapshot(
    prior + (snap.alpha - prior) * lambda,
    prior + (snap.beta - prior) * lambda,
  );
}

/// The three-level difficulty ratchet (#103, PUNTENFORMULE §2.5): the
/// highest difficulty at which this LO ever earned a positive signal.
///
/// A positive at [difficulty] lifts [current] to `max(current, difficulty)`;
/// anything else — negatives, neutrals — leaves it alone. Strength does not
/// matter: a weak positive at hard is still a positive at hard, the same
/// rule the calibration-relative ratchet (`lastPositiveAtCalibratedAt`)
/// uses. Follow-up grading is the caller's business: it is not a calibrated
/// probe and must not reach this function (CONDUCTOR_POLICY §6.2).
QuestionDifficulty? ratchetHighestPositiveDifficulty({
  required QuestionDifficulty? current,
  required LoSignalKind kind,
  required QuestionDifficulty difficulty,
}) {
  if (kind != LoSignalKind.positive) return current;
  if (current == null || difficulty.index > current.index) return difficulty;
  return current;
}

/// Per-LO mastery condition 1 (mean) and 2 (evidence). Condition 3
/// (`lastPositiveAtCalibratedAt` non-null) and condition 4 (the right own
/// questions, [meetsOwnQuestionsCondition]) are stored alongside the
/// belief, not derivable from `(α, β)` alone; [isMastered] reads all four.
bool meetsMasteryMeanAndEvidence(BeliefSnapshot snap) {
  return snap.mean >= PolicyConstants.masteryMeanThreshold &&
      snap.evidence >= PolicyConstants.masteryEvidenceMin;
}

/// Per-LO mastery condition 4 (#279, formula 1.1, CONDUCTOR_POLICY §4.1):
/// at least `masteryRightOwnQuestionsMin` own questions answered right
/// ([ownQuestionsRight], `LoBelief.ownQuestionsRight`), of which at least
/// `masteryRightNonMcqQuestionsMin` no multiple choice
/// ([ownQuestionsRightNonMcq]). A side signal, a follow-up and a transfer
/// credit move `(α, β)` but count for neither. A count the doc does not
/// have reads 0 — the teacher's choice: a doc from before 1.1 earns them
/// anew, unless the release fills them from `turn_history` (#281).
bool meetsOwnQuestionsCondition({
  required int? ownQuestionsRight,
  required int? ownQuestionsRightNonMcq,
}) {
  return (ownQuestionsRight ?? 0) >=
          PolicyConstants.masteryRightOwnQuestionsMin &&
      (ownQuestionsRightNonMcq ?? 0) >=
          PolicyConstants.masteryRightNonMcqQuestionsMin;
}

/// Whether an LO is mastered now (CONDUCTOR_POLICY §4.1): [snap] is its
/// decayed belief, [belief] its doc (`null`: never written, not mastered).
///
/// Conditions 1 and 2 on [snap], condition 3 (a positive at calibration),
/// and condition 4 ([meetsOwnQuestionsCondition]) — unless the LO has its
/// stamp ([everMastered]: `firstMasteredAt`, or the reading of an old doc
/// without it): a stamp that is there stays (#168), and the LO it marks
/// met condition 4 when it was set, or was set before condition 4 existed
/// (#279). Such an LO is mastered again on conditions 1–3 after a dip, as
/// it was before 1.1; a stamp from before 1.1 on few own questions is
/// #275's to bring back, not the live reading's.
///
/// What every live reading of mastery uses: the selection (§2.1), the
/// subgoal's advance and its cached share (§4.2, §4.5), the cascade skip,
/// the bar's full segment (§4.5).
bool isMastered(BeliefSnapshot snap, LoBelief? belief) {
  if (belief == null) return false;
  if (belief.lastPositiveAtCalibratedAt == null) return false;
  if (!meetsMasteryMeanAndEvidence(snap)) return false;
  return everMasteredBelief(belief) ||
      meetsOwnQuestionsCondition(
        ownQuestionsRight: belief.ownQuestionsRight,
        ownQuestionsRightNonMcq: belief.ownQuestionsRightNonMcq,
      );
}

/// Whether one right answer at [calibration] would meet conditions 1 and 2
/// of §4.1 on [snap]: a `(positive, strong)` with the home factor (× 1.0)
/// — the lower bound — applied as every answer is, forgetting and then the
/// cap (§3.4, #278). [multipleChoice]: the answer is a pick (#279), half
/// the weight. Condition 3 that answer meets itself; condition 4 is the
/// caller's.
bool oneRightAnswerMeetsMeanAndEvidence({
  required BeliefSnapshot snap,
  required QuestionDifficulty calibration,
  bool multipleChoice = false,
}) {
  final deltas = signalDeltas(
    kind: LoSignalKind.positive,
    strength: LoSignalStrength.strong,
    difficulty: calibration,
    provenance: EvidenceProvenance.home,
    multipleChoice: multipleChoice,
  );
  final next = applyEvidence(
    alpha: snap.alpha,
    beta: snap.beta,
    alphaDelta: deltas.alphaDelta,
    betaDelta: deltas.betaDelta,
  );
  return meetsMasteryMeanAndEvidence(next);
}

/// Whether right picks alone — strong multiple-choice answers at
/// [difficulty] at home, one after another — can ever bring an LO to
/// conditions 1 and 2 of §4.1 (#279). With forgetting (§3.4) a run of them
/// holds `α` under `1 + w / (1 − λ)` for the pick's weight `w`: at easy 3,
/// at medium 4.33 (evidence 5.33, under 5.75), at hard 5.67. Only on hard
/// do picks get there.
bool picksAloneCanMaster(QuestionDifficulty difficulty) {
  final w = signalDeltas(
    kind: LoSignalKind.positive,
    strength: LoSignalStrength.strong,
    difficulty: difficulty,
    multipleChoice: true,
  ).alphaDelta;
  const prior = PolicyConstants.prior;
  return meetsMasteryMeanAndEvidence(
    BeliefSnapshot(prior + w / (1 - PolicyConstants.forgetFactor), prior),
  );
}

/// The type rule of #279 (CONDUCTOR_POLICY §2.2): whether the next
/// question on an LO that is not mastered now should be no multiple
/// choice, because a right pick can no longer bring it to its stamp.
/// [snap] is its decayed belief, [belief] its doc, [calibration] the level
/// the stamp is earned at.
///
/// Before the LO's first right own answer a pick is the gentle way in, as
/// it was: no rule. After it, no pick when
///
///   1. **the right non-pick is missing** — no stamp, and no right own
///      question that was no multiple choice: condition 4 can only be met
///      by another type. The teacher's rule ("ontbreekt alleen de open
///      vraag nog").
///   2. **picks cannot get there** — at [calibration] a run of right picks
///      never reaches conditions 1 and 2 ([picksAloneCanMaster]): on easy
///      and medium an LO asked only as multiple choice would never be
///      mastered, at home.
///   3. **the next right answer decides** — one right answer of another
///      type would master it, a right pick would not: the bar shows that
///      segment half (§4.5), and the answer should count.
///
/// An LO without a doc gets no rule, and one whose kind has no other type
/// is the caller's.
bool needsNonMcqQuestion({
  required BeliefSnapshot snap,
  required LoBelief? belief,
  required QuestionDifficulty calibration,
}) {
  if (belief == null) return false;
  final stamped = belief.firstMasteredAt != null;
  if (!stamped && (belief.ownQuestionsRight ?? 0) == 0) return false;
  if (!stamped &&
      (belief.ownQuestionsRightNonMcq ?? 0) <
          PolicyConstants.masteryRightNonMcqQuestionsMin) {
    return true;
  }
  if (!picksAloneCanMaster(calibration)) return true;
  return oneRightAnswerMeetsMeanAndEvidence(
        snap: snap,
        calibration: calibration,
      ) &&
      !oneRightAnswerMeetsMeanAndEvidence(
        snap: snap,
        calibration: calibration,
        multipleChoice: true,
      );
}

/// Stuck rule (CONDUCTOR_POLICY 4.4, #278). Computed live, never stored.
///
/// Stuck = tried enough, and still not getting it: at least
/// `stuckOwnQuestionsMin` own questions on the LO ([ownQuestions],
/// `LoBelief.ownQuestions`) AND the decayed mean [snap] under
/// `stuckMeanCeiling`. Counted in questions since formula 1.1: forgetting
/// keeps `α + β` bounded, so the evidence no longer says how often the
/// student tried. A doc from before the count reads 0, so its LO is stuck
/// only after six new own questions.
bool isStuck(BeliefSnapshot snap, {required int ownQuestions}) {
  return ownQuestions >= PolicyConstants.stuckOwnQuestionsMin &&
      snap.mean < PolicyConstants.stuckMeanCeiling;
}
