// The grade formula (#99, PUNTENFORMULE part 2). Pure arithmetic, no I/O:
// `GradeProposalService` gathers the inputs, this module turns them into
// the numbers the document promises a student can recompute by hand.
//
// No LLM anywhere in here — the model writes the narrative *around* the
// number (`grade_justification.dart`); it never picks it.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';

import 'milestone.dart';

/// Open parameters of PUNTENFORMULE §4. Every value here is the *v1
/// placeholder* the document marks TBD-with-procedure: the period-1 shadow
/// run fits them, version 1.1 of the document freezes them. Bijlage B's
/// worked example uses exactly these, so the unit tests reproduce it.
class GradingConstants {
  GradingConstants._();

  /// Version of PUNTENFORMULE.md these constants implement. Stamped on
  /// every persisted proposal so a later parameter change (which only
  /// applies at a period boundary, §5) can never be mistaken for the one
  /// a signed grade was computed under.
  static const String formulaVersion = '1.0.16';

  /// Above-50 weights: extension (`u`) vs. hard-level demonstration
  /// (`d`). Sum to 1 (§2.3).
  static const double weightExtension = 0.6;
  static const double weightDifficulty = 0.4;

  /// The curve under the 50 (§2.3): `C(k) = k` in v1.
  static double curve(double k) => k;
}

/// What the formula reads per LO on the report moment (§2.2): **mastered**
/// is the one-way `firstMasteredAt` stamp (#168, v1.0.12) — has this LO
/// *ever* met the three conditions of §1.5 — plus the three-level
/// difficulty ratchet of §2.5.
///
/// The live belief is not consulted for mastery. It is designed to move:
/// that is its job for the tutor (question choice, stuck detection, the
/// warm-up review, `regressedAt`), and it keeps doing that unchanged. A
/// grade is a record of what was demonstrated, and a later measurement
/// that disappoints — an incidental cross-subgoal negative (#167), a bad
/// day, decay — does not undo a demonstration. The split: the belief
/// steers the teaching, the stamp steers the grade. It also makes the
/// grade monotone in the student's work: continuing to work can never
/// lower it.
///
/// Reading the live belief hit exactly the wrong student. The tutor stops
/// probing a mastered LO, so a strong student ends on thin evidence
/// (α ≈ 4–5, the mastery bar itself); any single later signal pushes that
/// under mean 0,80, and because mastered LOs are not re-probed it stays
/// there. v1.0.10 took decay out of this path for that reason; the stamp
/// subsumes it — nothing that happens to (α, β) after the stamp fell can
/// reach the grade. Nor does this rest the grade on few judgements: the
/// stamp falls only when the *accumulated* direct evidence crosses the
/// bar, so one wrong AI verdict can delay it, never remove it.
///
/// A doc without the stamp is not mastered, also when its stored (α, β)
/// and ratchet would meet §1.5 today. The conductor's fallback for docs
/// from before the field existed (`belief_math.everMastered`) is
/// deliberately not applied here: it is a live reading, and for the
/// students it concerns (old clients, #165) it would quietly keep the grade
/// on the belief. Such docs get their stamp from a one-off reconstruction
/// out of `turn_history`, outside the app, before this version ships.
class LoGradeInput {
  const LoGradeInput({required this.mastered, required this.highest});

  final bool mastered;
  final QuestionDifficulty? highest;

  /// Reads one belief doc as stored. A missing doc is an LO that was
  /// never probed: not mastered, nothing demonstrated.
  ///
  /// Mastery is the stamp and nothing else. The level is the ratchet; a
  /// doc without a ratchet level but with the old calibrated-positive flag
  /// set is read the way §2.5 says old data reads — "demonstrated at
  /// non-easy", i.e. [QuestionDifficulty.medium]. That reading lives here,
  /// in the formula, and only here (#164): the model keeps such a doc's
  /// level `null`, so a guess is never written to Cosmos as if it had been
  /// measured, and the next positive records the level actually asked.
  factory LoGradeInput.fromBelief(LoBelief? belief) {
    if (belief == null) {
      return const LoGradeInput(mastered: false, highest: null);
    }
    final calibratedPositive = belief.lastPositiveAtCalibratedAt != null;
    return LoGradeInput(
      mastered: belief.firstMasteredAt != null,
      highest:
          belief.highestPositiveDifficulty ??
          (calibratedPositive ? QuestionDifficulty.medium : null),
    );
  }
}

/// One LO of a milestone with its Angoff side.
class MilestoneLo {
  const MilestoneLo({
    required this.subgoalId,
    required this.loId,
    required this.isCore,
  });

  final String subgoalId;
  final String loId;
  final bool isCore;

  String get key => Milestone.loKey(subgoalId, loId);
}

/// The mastery score M and the three fractions it is built from (§2.2–§2.3),
/// with the raw counts so the teacher UI (and the justification prompt)
/// can show "7 of 8 core LOs" instead of `k = 0.875`.
class MasteryScore {
  const MasteryScore({
    required this.k,
    required this.u,
    required this.d,
    required this.m,
    required this.coreTotal,
    required this.coreCounted,
    required this.extensionTotal,
    required this.extensionMastered,
    required this.masteredTotal,
    required this.hardCount,
  });

  final double k;
  final double u;
  final double d;

  /// Mastery score on 100.
  final double m;

  final int coreTotal;

  /// Core LOs that are mastered *and* demonstrated at the milestone's
  /// expected difficulty or above.
  final int coreCounted;
  final int extensionTotal;
  final int extensionMastered;

  /// Mastered LOs across K ∪ U (plain §1.5 mastery, no difficulty gate).
  final int masteredTotal;

  /// Of those, the ones whose ratchet stands on `hard`.
  final int hardCount;
}

/// `M = 50·C(k) + 50·k·(w_u·u + w_d·d)` over the milestone's LOs (§2.3).
///
/// [inputs] is keyed by `Milestone.loKey`; an LO without an entry counts as
/// never probed. Edge cases the document leaves implicit: an empty K gates
/// nothing (`k = 1`) as long as there is *something* in the milestone (an
/// empty milestone scores 0), an empty U earns nothing above the 50
/// through `u`, and `d` is 0 when nothing is mastered.
MasteryScore computeMasteryScore({
  required List<MilestoneLo> los,
  required Map<String, LoGradeInput> inputs,
  required QuestionDifficulty expectedDifficulty,
}) {
  var coreTotal = 0;
  var coreCounted = 0;
  var extTotal = 0;
  var extMastered = 0;
  var masteredTotal = 0;
  var hardCount = 0;

  for (final lo in los) {
    final input =
        inputs[lo.key] ?? const LoGradeInput(mastered: false, highest: null);
    final highest = input.highest;
    if (input.mastered) {
      masteredTotal += 1;
      if (highest == QuestionDifficulty.hard) hardCount += 1;
    }
    if (lo.isCore) {
      coreTotal += 1;
      final atLevel =
          highest != null && highest.index >= expectedDifficulty.index;
      if (input.mastered && atLevel) coreCounted += 1;
    } else {
      extTotal += 1;
      if (input.mastered) extMastered += 1;
    }
  }

  final k = coreTotal == 0
      ? (los.isEmpty ? 0.0 : 1.0)
      : coreCounted / coreTotal;
  final u = extTotal == 0 ? 0.0 : extMastered / extTotal;
  final d = masteredTotal == 0 ? 0.0 : hardCount / masteredTotal;
  final m = masteryFromFractions(k: k, u: u, d: d);

  return MasteryScore(
    k: k,
    u: u,
    d: d,
    m: m,
    coreTotal: coreTotal,
    coreCounted: coreCounted,
    extensionTotal: extTotal,
    extensionMastered: extMastered,
    masteredTotal: masteredTotal,
    hardCount: hardCount,
  );
}

/// The §2.3 arithmetic on already-known fractions.
double masteryFromFractions({
  required double k,
  required double u,
  required double d,
}) {
  final above =
      GradingConstants.weightExtension * u +
      GradingConstants.weightDifficulty * d;
  return 50 * GradingConstants.curve(k) + 50 * k * above;
}

/// `P = M` (§2.6, v1.0.16), before rounding. The proposal is the mastery
/// score on the stamps and nothing else: the growth term G, and with it
/// `M_start` and the period-start snapshot, is gone (#191) — exactly what
/// `tooling/evaluation/rules.py` computes outside the app.
double proposalScore({required double mEnd}) => mEnd;

/// The proposal as it goes to the teacher: a whole point on 100.
int roundedProposal(double p) => p.round().clamp(0, 100);
