// All numeric / threshold constants the conductor reads.
//
// Adjusting calibration is meant to live here so behaviour can be tuned
// without code archaeology. Front-matter note in
// `docs/CONDUCTOR_POLICY.md`: every constant in sections 3–5 lives in one
// named module — this is it. Where the code value differs from the doc
// value, the code value wins; flag the discrepancy in the PR description.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';

class PolicyConstants {
  PolicyConstants._();

  // ---- Belief update (CONDUCTOR_POLICY §3) -------------------------------

  /// Beta prior; an unprobed LO starts at (1, 1).
  static const double prior = 1.0;

  /// Cap on `α + β`. Beyond this, existing evidence shrinks toward the prior
  /// before new evidence is applied (see `belief_math.applyEvidence`).
  static const double evidenceCap = 20.0;

  /// Decay half-life. `α_eff = 1 + (α - 1) * 0.5^(elapsed_days/halfLife)`.
  static const Duration decayHalfLife = Duration(days: 60);

  /// Base `(α, β)` deltas per `(signal, strength)` from the LLM grader.
  /// `neutral` is a no-op — never represented here.
  static const double weightStrong = 2.0;
  static const double weightModerate = 1.0;
  static const double weightWeak = 0.5;

  /// Difficulty multiplier on the base weight. `correct` at hard is more
  /// diagnostic than at easy; `wrong` at hard is *less* diagnostic than at
  /// easy.
  static double difficultyMultiplier(QuestionDifficulty d) {
    switch (d) {
      case QuestionDifficulty.easy:
        return 0.6;
      case QuestionDifficulty.medium:
        return 1.0;
      case QuestionDifficulty.hard:
        return 1.4;
    }
  }

  /// Provenance multiplier `s` on the base weight (PUNTENFORMULE §2.7, #100).
  /// Evidence produced under Anchor supervision is *more reliable*, not
  /// certain, so the factor is modest. Provisional until the period-1 shadow
  /// run fixes it (PUNTENFORMULE §4); must stay ≥ 1 — home evidence is never
  /// discounted, it is confirmed or contradicted by later supervised work.
  static const double supervisedWeightFactor = 1.25;

  /// Multiplier for a signal's provenance. `home` is the unit weight.
  static double provenanceMultiplier(EvidenceProvenance p) {
    switch (p) {
      case EvidenceProvenance.home:
        return 1.0;
      case EvidenceProvenance.supervised:
        return supervisedWeightFactor;
    }
  }

  /// Weight applied to follow-up answer signals. Per CONDUCTOR_POLICY §6.2,
  /// follow-up signals are capped at `weak` and treated as `medium`
  /// difficulty for the multiplier step. (Follow-up chaining is out of scope
  /// for the current step but the constant lives here for completeness.)
  static const double followUpStrengthCap = weightWeak;

  // ---- Mastery (CONDUCTOR_POLICY §4) -------------------------------------

  /// Per-LO mastery: belief mean ≥ this.
  static const double masteryMeanThreshold = 0.8;

  /// Per-LO mastery: `α + β ≥ this` (beyond the prior).
  static const double masteryEvidenceMin = 4.0;

  /// Stuck rule: `α + β ≥ this` AND mean < `stuckMeanCeiling` → stuck.
  static const double stuckEvidenceMin = 8.0;
  static const double stuckMeanCeiling = 0.6;

  /// "Practiceable" — `α + β < cap - this` is fresh enough to probe.
  /// Used for the saturation-detection branch on a fully-mastered subgoal.
  static const double saturationSlack = 2.0;

  /// Saturated-stuck rule: a non-practiceable LO whose mean is below this
  /// ceiling is also stuck. The cap-then-shrink update in
  /// `belief_math.applyEvidence` slows mean movement to a crawl once the
  /// LO is at the evidence cap, so re-probing rarely catches up; the
  /// student is better served by advancing. Set just below
  /// `masteryMeanThreshold` so LOs within one good probe of mastery are
  /// not prematurely written off.
  static const double stuckSaturatedMeanCeiling = 0.75;

  /// Cap on the cascade-skip when advancing through pre-mastered subgoals.
  /// At most this many subgoals can auto-skip in a row.
  static const int cascadeSkipCap = 1;

  // ---- Warm-up review (CONDUCTOR_POLICY §1.5, #102) ------------------------

  /// How long a once-mastered LO in another subgoal must go without a
  /// belief write before it is due for a warm-up review question. Half the
  /// decay half-life: at that age a `(5, 1)` belief has decayed to
  /// `(3.8, 1)` — mean 0.79, just under the mastery threshold — so the
  /// review lands right where decay starts to read as "forgotten". Any
  /// write resets the clock, including a transfer credit (§3.7), which is
  /// how LOs that recur in later work stay out of the warm-up pool. An LO
  /// flagged `regressedAt` (#112) is due regardless of this clock.
  static const Duration warmUpStaleAfter = Duration(days: 30);

  // ---- Calibration (CONDUCTOR_POLICY §5) ---------------------------------

  /// Recent-answer window size on the account doc.
  static const int calibrationWindow = 10;

  /// Promotion: ≥ `promotionMinSamples` at-calibrated answers in the window
  /// AND fraction-correct ≥ `promotionCorrectRatio`.
  static const int promotionMinSamples = 4;
  static const double promotionCorrectRatio = 0.75;

  /// Demotion: ≥ `demotionMinSamples` at-calibrated answers in the window
  /// AND fraction (wrong+partial) ≥ `demotionBadRatio`.
  static const int demotionMinSamples = 3;
  static const double demotionBadRatio = 0.60;

  /// Cap promotion/demotion at one notch per check.
  static const int calibrationStepCap = 1;

  // ---- LLM contract failure (CONDUCTOR_POLICY §7.3) ----------------------

  /// Sustained-failure rule: enter degraded mode when `degradedThreshold` of
  /// the last `degradedWindow` grading calls fell back.
  static const int degradedWindow = 5;
  static const int degradedThreshold = 3;

  // ---- Teacher-dashboard signal events (CONDUCTOR_POLICY §8.2) -----------

  /// Repeated-demotions strong-signal threshold. Three consecutive demotions
  /// (no intervening promotion) on the same student fires
  /// `repeatedDemotions`. The doc says "tunable; suggest 3."
  static const int repeatedDemotionsThreshold = 3;

  // ---- Follow-up chains (CONDUCTOR_POLICY §6.4) --------------------------

  /// Default depth limit for follow-up chains. Original probe + N follow-ups
  /// allowed when the subgoal does not opt in.
  static const int followUpDepthDefault = 1;

  /// Depth limit when the active subgoal has `allowChains: true`.
  static const int followUpDepthWithChains = 2;

  // ---- Recent question type ring buffer (STUDENT_MODEL §3) ---------------

  /// Window on the account doc for cross-LO type variety.
  static const int recentQuestionTypesWindow = 5;
}
