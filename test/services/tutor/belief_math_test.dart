import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyDecay', () {
    test('lastUpdatedAt == now → unchanged', () {
      final now = DateTime.utc(2026, 5, 9);
      final s = applyDecay(alpha: 8, beta: 2, lastUpdatedAt: now, now: now);
      expect(s.alpha, 8);
      expect(s.beta, 2);
    });

    test('half-life elapsed shrinks excess by half', () {
      final lastUpdatedAt = DateTime.utc(2026, 1, 1);
      final now = lastUpdatedAt.add(PolicyConstants.decayHalfLife);
      final s = applyDecay(
        alpha: 9,
        beta: 3,
        lastUpdatedAt: lastUpdatedAt,
        now: now,
      );
      // α: 1 + (9-1)*0.5 = 5.0
      expect(s.alpha, closeTo(5.0, 1e-9));
      // β: 1 + (3-1)*0.5 = 2.0
      expect(s.beta, closeTo(2.0, 1e-9));
    });

    test('untouched for years drifts toward (1, 1)', () {
      final lastUpdatedAt = DateTime.utc(2020, 1, 1);
      final now = DateTime.utc(2030, 1, 1);
      final s = applyDecay(
        alpha: 18,
        beta: 2,
        lastUpdatedAt: lastUpdatedAt,
        now: now,
      );
      expect(s.alpha, closeTo(1.0, 0.01));
      expect(s.beta, closeTo(1.0, 0.01));
    });
  });

  group('transferCreditDeltas (#101)', () {
    test('is a weak positive as medium: α += 0.5, β untouched', () {
      final d = transferCreditDeltas();
      expect(d.alphaDelta, closeTo(PolicyConstants.weightWeak, 1e-9));
      expect(d.betaDelta, 0);
    });

    test('is weighted by provenance like any other signal', () {
      final d = transferCreditDeltas(provenance: EvidenceProvenance.supervised);
      expect(
        d.alphaDelta,
        closeTo(
          PolicyConstants.weightWeak * PolicyConstants.supervisedWeightFactor,
          1e-9,
        ),
      );
      expect(d.betaDelta, 0);
    });

    test('never exceeds the weak weight at home', () {
      expect(
        transferCreditDeltas().alphaDelta,
        lessThanOrEqualTo(PolicyConstants.weightWeak),
      );
    });
  });

  group('everMastered (#101)', () {
    final stamp = DateTime.utc(2026, 5, 1);
    final ratchet = DateTime.utc(2026, 4, 1);

    test('the stamp alone decides, whatever the stored values say', () {
      expect(
        everMastered(
          firstMasteredAt: stamp,
          alpha: 1,
          beta: 1,
          lastPositiveAtCalibratedAt: null,
        ),
        isTrue,
      );
    });

    test('without the stamp: mastered as of the last write counts', () {
      // (5, 1): mean 0.83, evidence 6, ratchet set → was mastered.
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 5,
          beta: 1,
          lastPositiveAtCalibratedAt: ratchet,
        ),
        isTrue,
      );
    });

    test('without the stamp: mean or evidence below mastery is not', () {
      // (3, 1): mean 0.75.
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 3,
          beta: 1,
          lastPositiveAtCalibratedAt: ratchet,
        ),
        isFalse,
      );
      // (2.5, 0.5)... evidence 3 < 4 even though mean is 0.83.
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 2.5,
          beta: 0.5,
          lastPositiveAtCalibratedAt: ratchet,
        ),
        isFalse,
      );
    });

    test('without the stamp: no calibrated positive is never mastered', () {
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 9,
          beta: 1,
          lastPositiveAtCalibratedAt: null,
        ),
        isFalse,
      );
    });
  });

  group('nextRegressedAt (#112, #167)', () {
    final now = DateTime.utc(2026, 9, 3, 10);
    final earlier = DateTime.utc(2026, 8, 20);

    DateTime? next({
      DateTime? current,
      bool directProbe = false,
      bool everMastered = true,
      bool negative = true,
    }) => nextRegressedAt(
      current: current,
      directProbe: directProbe,
      everMastered: everMastered,
      negative: negative,
      now: now,
    );

    test('an incidental negative on a once-mastered LO sets it', () {
      expect(next(), now);
    });

    test('an already set flag is kept, so the oldest open question wins', () {
      expect(next(current: earlier), earlier);
    });

    test('a direct probe clears it whichever way the answer went', () {
      expect(next(directProbe: true, current: earlier), isNull);
      expect(
        next(directProbe: true, current: earlier, negative: false),
        isNull,
      );
    });

    test('an LO never mastered is not review material: never flagged', () {
      expect(next(everMastered: false), isNull);
      expect(next(everMastered: false, current: earlier), isNull);
    });

    test('an indirect positive (credit, incidental) leaves it as it was: '
        'good news from the side does not answer the question, the review '
        'does (#167)', () {
      expect(next(negative: false, current: earlier), earlier);
      expect(next(negative: false, current: null), isNull);
    });
  });

  group('signalDeltas', () {
    test('positive strong @ medium → α += 2.0', () {
      final d = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
      );
      expect(d.alphaDelta, closeTo(2.0, 1e-9));
      expect(d.betaDelta, 0);
    });

    test('negative moderate @ hard → β += 0.6: a mistake above the level '
        'says little about it (#169)', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.hard,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(0.6, 1e-9));
    });

    test('negative moderate @ easy → β += 1.4: a mistake below the level '
        'says a lot (#169)', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.easy,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(1.4, 1e-9));
    });

    test('negative strong @ medium → β += 2.0: medium is the unit for both '
        'signs', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(2.0, 1e-9));
    });

    test('positive moderate @ hard → α += 1.4: positives are unchanged by '
        '#169', () {
      final d = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.hard,
      );
      expect(d.alphaDelta, closeTo(1.4, 1e-9));
      expect(d.betaDelta, 0);
    });

    test('positive weak @ easy → α += 0.3', () {
      final d = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.weak,
        difficulty: QuestionDifficulty.easy,
      );
      expect(d.alphaDelta, closeTo(0.3, 1e-9));
      expect(d.betaDelta, 0);
    });

    test('neutral is a no-op regardless of strength or difficulty', () {
      final d = signalDeltas(
        kind: LoSignalKind.neutral,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.hard,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, 0);
    });
  });

  group('difficulty factor asymmetry (#169, PUNTENFORMULE §1.2)', () {
    QuestionDifficulty mirror(QuestionDifficulty d) => switch (d) {
      QuestionDifficulty.easy => QuestionDifficulty.hard,
      QuestionDifficulty.medium => QuestionDifficulty.medium,
      QuestionDifficulty.hard => QuestionDifficulty.easy,
    };

    /// The mean a belief settles on when a fraction [correct] of strong
    /// answers at [level] is right and the rest wrong: what μ reads as
    /// "accuracy" at that level once the prior is negligible.
    double meanAt(QuestionDifficulty level, double correct) {
      final up = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: level,
      ).alphaDelta;
      final down = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.strong,
        difficulty: level,
      ).betaDelta;
      final alpha = correct * up;
      final beta = (1 - correct) * down;
      return alpha / (alpha + beta);
    }

    test('the negative factor is the mirror image of the positive one', () {
      for (final d in QuestionDifficulty.values) {
        expect(
          PolicyConstants.negativeDifficultyMultiplier(d),
          PolicyConstants.positiveDifficultyMultiplier(mirror(d)),
          reason: 'negative at $d should equal positive at ${mirror(d)}',
        );
      }
      expect(
        PolicyConstants.positiveDifficultyMultiplier(QuestionDifficulty.medium),
        1.0,
      );
      expect(
        PolicyConstants.negativeDifficultyMultiplier(QuestionDifficulty.medium),
        1.0,
      );
    });

    test('μ is level-aware: the 0,80 mastery bar is ~90% raw accuracy at '
        'easy, 80% at medium and ~63% at hard', () {
      const bar = PolicyConstants.masteryMeanThreshold;
      expect(meanAt(QuestionDifficulty.easy, 0.90), closeTo(bar, 0.01));
      expect(meanAt(QuestionDifficulty.medium, 0.80), closeTo(bar, 1e-9));
      expect(meanAt(QuestionDifficulty.hard, 0.63), closeTo(bar, 0.01));
      // The same 80% raw reads very differently by level.
      expect(meanAt(QuestionDifficulty.easy, 0.80), lessThan(0.65));
      expect(meanAt(QuestionDifficulty.hard, 0.80), greaterThan(0.90));
    });

    test('a promotion on the calibration ladder is μ-neutral: 76% at medium '
        'and the ~60% that follows at hard read the same', () {
      final atMedium = meanAt(QuestionDifficulty.medium, 0.76);
      final atHard = meanAt(QuestionDifficulty.hard, 0.60);
      expect(atMedium, closeTo(0.76, 1e-9));
      expect(atHard, closeTo(0.78, 0.01));
      expect((atHard - atMedium).abs(), lessThan(0.03));
    });

    test('the saturated-stuck ceiling reads the level too: at hard it is '
        '~57% raw, not 75%', () {
      const ceiling = PolicyConstants.stuckSaturatedMeanCeiling;
      expect(meanAt(QuestionDifficulty.hard, 0.5625), closeTo(ceiling, 1e-3));
      expect(meanAt(QuestionDifficulty.medium, 0.75), closeTo(ceiling, 1e-9));
    });
  });

  group('signalDeltas provenance (#100, PUNTENFORMULE §2.7)', () {
    const s = PolicyConstants.supervisedWeightFactor;

    test('the supervised factor is modest and never below 1', () {
      expect(s, greaterThanOrEqualTo(1.0));
      expect(s, lessThanOrEqualTo(1.5));
      expect(
        PolicyConstants.provenanceMultiplier(EvidenceProvenance.home),
        1.0,
      );
      expect(
        PolicyConstants.provenanceMultiplier(EvidenceProvenance.supervised),
        s,
      );
    });

    test('home is the default and equals the unweighted delta', () {
      final implicit = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
      );
      final explicit = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
        provenance: EvidenceProvenance.home,
      );
      expect(implicit.alphaDelta, closeTo(2.0, 1e-9));
      expect(explicit.alphaDelta, closeTo(2.0, 1e-9));
    });

    test('supervised positive strong @ medium → α += 2.0 × s', () {
      final d = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
        provenance: EvidenceProvenance.supervised,
      );
      expect(d.alphaDelta, closeTo(2.0 * s, 1e-9));
      expect(d.betaDelta, 0);
    });

    test('symmetric in sign where difficulty is not (#169): supervised '
        'negative moderate @ hard → β += 0.6 × s', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.hard,
        provenance: EvidenceProvenance.supervised,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(0.6 * s, 1e-9));
    });

    test('neutral stays a no-op under supervision', () {
      final d = signalDeltas(
        kind: LoSignalKind.neutral,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
        provenance: EvidenceProvenance.supervised,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, 0);
    });
  });

  group('ratchetHighestPositiveDifficulty (#103, PUNTENFORMULE §2.5)', () {
    test('the first positive sets the level to the difficulty asked', () {
      for (final level in QuestionDifficulty.values) {
        expect(
          ratchetHighestPositiveDifficulty(
            current: null,
            kind: LoSignalKind.positive,
            difficulty: level,
          ),
          level,
        );
      }
    });

    test('a positive at a higher difficulty lifts the level', () {
      expect(
        ratchetHighestPositiveDifficulty(
          current: QuestionDifficulty.easy,
          kind: LoSignalKind.positive,
          difficulty: QuestionDifficulty.medium,
        ),
        QuestionDifficulty.medium,
      );
      expect(
        ratchetHighestPositiveDifficulty(
          current: QuestionDifficulty.medium,
          kind: LoSignalKind.positive,
          difficulty: QuestionDifficulty.hard,
        ),
        QuestionDifficulty.hard,
      );
    });

    test('one-way: a positive at a lower difficulty never lowers it', () {
      expect(
        ratchetHighestPositiveDifficulty(
          current: QuestionDifficulty.hard,
          kind: LoSignalKind.positive,
          difficulty: QuestionDifficulty.easy,
        ),
        QuestionDifficulty.hard,
      );
      expect(
        ratchetHighestPositiveDifficulty(
          current: QuestionDifficulty.medium,
          kind: LoSignalKind.positive,
          difficulty: QuestionDifficulty.medium,
        ),
        QuestionDifficulty.medium,
      );
    });

    test('negatives and neutrals leave it alone, at any level', () {
      for (final kind in [LoSignalKind.negative, LoSignalKind.neutral]) {
        expect(
          ratchetHighestPositiveDifficulty(
            current: null,
            kind: kind,
            difficulty: QuestionDifficulty.hard,
          ),
          isNull,
        );
        expect(
          ratchetHighestPositiveDifficulty(
            current: QuestionDifficulty.medium,
            kind: kind,
            difficulty: QuestionDifficulty.hard,
          ),
          QuestionDifficulty.medium,
        );
      }
    });
  });

  group('applyEvidence', () {
    test('below cap → simple addition', () {
      final s = applyEvidence(alpha: 4, beta: 1, alphaDelta: 2, betaDelta: 0);
      expect(s.alpha, 6);
      expect(s.beta, 1);
    });

    test('at cap, strong-negative shrinks mass and applies new evidence', () {
      // (18, 2): mean 0.9, evidence 20 = cap.
      final s = applyEvidence(
        alpha: 18,
        beta: 2,
        alphaDelta: 0,
        betaDelta: 2.0,
      );
      // After shrink + add, α + β must equal cap.
      expect(s.alpha + s.beta, closeTo(PolicyConstants.evidenceCap, 1e-9));
      // Mean should drop materially below 0.9.
      expect(s.mean, lessThan(0.85));
    });

    test('zero-delta is a no-op', () {
      final s = applyEvidence(alpha: 4, beta: 2, alphaDelta: 0, betaDelta: 0);
      expect(s.alpha, 4);
      expect(s.beta, 2);
    });
  });

  group('mastery & stuck predicates', () {
    test('mean ≥ 0.8 AND evidence ≥ 4 → mastery condition met', () {
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(4, 1)), isTrue);
      // Just one signal short on mean.
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(3, 1)), isFalse);
      // Just one short on evidence.
      expect(
        meetsMasteryMeanAndEvidence(const BeliefSnapshot(2.4, 0.6)),
        isFalse,
      );
    });

    test('stuck: ≥ 8 evidence and mean < 0.6', () {
      expect(isStuck(const BeliefSnapshot(3, 6)), isTrue);
      // Above the stuck mean ceiling — not stuck.
      expect(isStuck(const BeliefSnapshot(7, 3)), isFalse);
      // Not enough evidence yet.
      expect(isStuck(const BeliefSnapshot(2, 4)), isFalse);
    });

    test('stuck (saturated): at evidence cap and mean < mastery', () {
      // (12, 6): mean 0.667, evidence 18 = cap - slack → saturated-stuck.
      expect(isStuck(const BeliefSnapshot(12, 6)), isTrue);
      // (14, 4): mean 0.778, evidence 18 → saturated but above the
      // saturated-stuck ceiling (0.75), so NOT stuck.
      expect(isStuck(const BeliefSnapshot(14, 4)), isFalse);
      // (10, 5): mean 0.667 but evidence 15 < cap - slack → practiceable,
      // not saturated, not stuck.
      expect(isStuck(const BeliefSnapshot(10, 5)), isFalse);
    });

    test('practiceable: evidence < cap - slack', () {
      expect(isPracticeable(const BeliefSnapshot(10, 5)), isTrue);
      // Right at the threshold.
      expect(
        isPracticeable(
          BeliefSnapshot(
            PolicyConstants.evidenceCap - PolicyConstants.saturationSlack,
            0,
          ),
        ),
        isFalse,
      );
    });
  });
}
