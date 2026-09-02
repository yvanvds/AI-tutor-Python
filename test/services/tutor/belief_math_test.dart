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

    test('negative moderate @ hard → β += 1.4', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.hard,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(1.4, 1e-9));
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

    test('symmetric: supervised negative moderate @ hard → β += 1.4 × s', () {
      final d = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.moderate,
        difficulty: QuestionDifficulty.hard,
        provenance: EvidenceProvenance.supervised,
      );
      expect(d.alphaDelta, 0);
      expect(d.betaDelta, closeTo(1.4 * s, 1e-9));
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
