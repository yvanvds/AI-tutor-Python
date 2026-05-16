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

  group('applyEvidence', () {
    test('below cap → simple addition', () {
      final s = applyEvidence(
        alpha: 4,
        beta: 1,
        alphaDelta: 2,
        betaDelta: 0,
      );
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
      final s = applyEvidence(
        alpha: 4,
        beta: 2,
        alphaDelta: 0,
        betaDelta: 0,
      );
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
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(2.4, 0.6)),
          isFalse);
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
        isPracticeable(BeliefSnapshot(
          PolicyConstants.evidenceCap - PolicyConstants.saturationSlack,
          0,
        )),
        isFalse,
      );
    });
  });
}
