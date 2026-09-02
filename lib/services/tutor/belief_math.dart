// Pure arithmetic primitives for the per-LO Beta belief.
//
// The conductor delegates every (α, β) calculation to this module so the
// arithmetic can be unit-tested in isolation, replayed at different
// constants in the future, and audited against `docs/CONDUCTOR_POLICY.md`
// §3–§4 line-by-line.

import 'dart:math' as math;

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
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
/// [provenance] applies the supervised weight factor `s`
/// (CONDUCTOR_POLICY §3.2, PUNTENFORMULE §2.7): symmetric in positive and
/// negative, like the difficulty multiplier, so it changes how *hard* a
/// piece of evidence is, not which way it points.
({double alphaDelta, double betaDelta}) signalDeltas({
  required LoSignalKind kind,
  required LoSignalStrength strength,
  required QuestionDifficulty difficulty,
  EvidenceProvenance provenance = EvidenceProvenance.home,
}) {
  if (kind == LoSignalKind.neutral) {
    return (alphaDelta: 0.0, betaDelta: 0.0);
  }
  final weighted =
      baseWeight(strength) *
      PolicyConstants.difficultyMultiplier(difficulty) *
      PolicyConstants.provenanceMultiplier(provenance);
  if (kind == LoSignalKind.positive) {
    return (alphaDelta: weighted, betaDelta: 0.0);
  }
  return (alphaDelta: 0.0, betaDelta: weighted);
}

/// Apply an evidence delta with the cap-then-add rule (CONDUCTOR_POLICY 3.4).
/// When the resulting `α + β` would exceed `PolicyConstants.evidenceCap`,
/// existing evidence-above-prior is shrunk proportionally to make room.
BeliefSnapshot applyEvidence({
  required double alpha,
  required double beta,
  required double alphaDelta,
  required double betaDelta,
}) {
  if (alphaDelta == 0 && betaDelta == 0) {
    return BeliefSnapshot(alpha, beta);
  }
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
/// (`lastPositiveAtCalibratedAt` non-null) is checked separately by the
/// conductor since it's stored alongside the belief, not derivable from
/// `(α, β)` alone.
bool meetsMasteryMeanAndEvidence(BeliefSnapshot snap) {
  return snap.mean >= PolicyConstants.masteryMeanThreshold &&
      snap.evidence >= PolicyConstants.masteryEvidenceMin;
}

/// Stuck rule (CONDUCTOR_POLICY 4.4). Computed live, never stored.
///
/// Two ways an LO can be stuck:
/// 1. Classic: enough evidence to be confident the student is not learning
///    (`α + β ≥ stuckEvidenceMin` AND `mean < stuckMeanCeiling`).
/// 2. Saturated: at the evidence cap but still below mastery
///    (`α + β ≥ cap - saturationSlack` AND `mean < stuckSaturatedMeanCeiling`).
///    The cap-then-shrink rule in `applyEvidence` makes mean movement too
///    slow to catch up once here, so further probes mostly spin in place.
bool isStuck(BeliefSnapshot snap) {
  final classic =
      snap.evidence >= PolicyConstants.stuckEvidenceMin &&
      snap.mean < PolicyConstants.stuckMeanCeiling;
  final saturated =
      snap.evidence >=
          PolicyConstants.evidenceCap - PolicyConstants.saturationSlack &&
      snap.mean < PolicyConstants.stuckSaturatedMeanCeiling;
  return classic || saturated;
}

/// Whether an LO can usefully be probed further given the cap.
bool isPracticeable(BeliefSnapshot snap) {
  return snap.evidence <
      PolicyConstants.evidenceCap - PolicyConstants.saturationSlack;
}
