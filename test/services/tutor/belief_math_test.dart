import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
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
          ownQuestionsRight: null,
          ownQuestionsRightNonMcq: null,
        ),
        isTrue,
      );
    });

    test('without the stamp: mastered as of the last write counts', () {
      // (5, 1): mean 0.83, evidence 6, ratchet set, two right own
      // questions, one no multiple choice → was mastered.
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 5,
          beta: 1,
          lastPositiveAtCalibratedAt: ratchet,
          ownQuestionsRight: 2,
          ownQuestionsRightNonMcq: 1,
        ),
        isTrue,
      );
    });

    test('without the stamp: condition 4 is today\'s too on a doc that '
        'keeps the counts (#279) — over the bar on fewer right own '
        'questions, or on picks alone, is not mastered', () {
      for (final (right, nonMcq) in [(1, 1), (3, 0), (0, 0)]) {
        expect(
          everMastered(
            firstMasteredAt: null,
            alpha: 5,
            beta: 1,
            lastPositiveAtCalibratedAt: ratchet,
            ownQuestionsRight: right,
            ownQuestionsRightNonMcq: nonMcq,
          ),
          isFalse,
          reason: '$right right, $nonMcq no multiple choice',
        );
      }
    });

    test('without the stamp and without the counts: a doc from before 1.1 '
        'is read by the rules of its day, a stamp they gave stays', () {
      expect(
        everMastered(
          firstMasteredAt: null,
          alpha: 5,
          beta: 1,
          lastPositiveAtCalibratedAt: ratchet,
          ownQuestionsRight: null,
          ownQuestionsRightNonMcq: null,
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
          ownQuestionsRight: 2,
          ownQuestionsRightNonMcq: 1,
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
          ownQuestionsRight: 2,
          ownQuestionsRightNonMcq: 1,
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
          ownQuestionsRight: 2,
          ownQuestionsRightNonMcq: 1,
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

    test('the stuck ceiling reads the level too: at hard it is ~39% raw, '
        'at medium 60%, at easy ~78%', () {
      const ceiling = PolicyConstants.stuckMeanCeiling;
      expect(meanAt(QuestionDifficulty.hard, 0.3913), closeTo(ceiling, 1e-3));
      expect(meanAt(QuestionDifficulty.medium, 0.60), closeTo(ceiling, 1e-9));
      expect(meanAt(QuestionDifficulty.easy, 0.7778), closeTo(ceiling, 1e-3));
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
    test('#278: forgets, then adds — the evidence above the prior shrinks '
        'by λ before the new evidence lands', () {
      expect(PolicyConstants.forgetFactor, 0.7);
      final s = applyEvidence(alpha: 4, beta: 2, alphaDelta: 2, betaDelta: 0);
      // (1 + 3 × 0.7, 1 + 1 × 0.7) + (2, 0).
      expect(s.alpha, closeTo(5.1, 1e-9));
      expect(s.beta, closeTo(1.7, 1e-9));
      final shrunk = forgetBeforeEvidence(const BeliefSnapshot(4, 2));
      expect(shrunk.alpha, closeTo(3.1, 1e-9));
      expect(shrunk.beta, closeTo(1.7, 1e-9));
    });

    test('#278: from the prior the first answer lands in full', () {
      final s = applyEvidence(alpha: 1, beta: 1, alphaDelta: 2, betaDelta: 0);
      expect(s.alpha, 3);
      expect(s.beta, 1);
    });

    test('zero-delta (a neutral) is a no-op: it forgets nothing', () {
      final s = applyEvidence(alpha: 4, beta: 2, alphaDelta: 0, betaDelta: 0);
      expect(s.alpha, 4);
      expect(s.beta, 2);
    });

    test('#278: the evidence stays bounded at 2 + w / (1 − λ), under the '
        'cap even for the heaviest answer', () {
      // Strong, hard, in the lesson time: 2.0 × 1.4 × 1.25 = 3.5.
      var snap = const BeliefSnapshot(1, 1);
      for (var i = 0; i < 200; i++) {
        snap = applyEvidence(
          alpha: snap.alpha,
          beta: snap.beta,
          alphaDelta: 3.5,
          betaDelta: 0,
        );
      }
      expect(snap.evidence, closeTo(2 + 3.5 / 0.3, 1e-9));
      expect(snap.evidence, lessThan(14));
    });

    test('#278: an old doc at the cap forgets below it at its next write, so '
        'one wrong answer moves μ more than the cap let it', () {
      // (18, 2): μ 0.9 at the cap. The cap alone shrank it to (16.1, 3.89),
      // μ 0.81; forgetting gives (12.9, 1.7) + (0, 2), μ 0.78.
      final s = applyEvidence(
        alpha: 18,
        beta: 2,
        alphaDelta: 0,
        betaDelta: 2.0,
      );
      expect(s.alpha, closeTo(12.9, 1e-9));
      expect(s.beta, closeTo(3.7, 1e-9));
      expect(s.evidence, lessThan(PolicyConstants.evidenceCap));
      expect(s.mean, closeTo(0.777, 1e-3));
    });

    test('the cap stays as a backstop: a doc over it is brought to it', () {
      final s = applyEvidence(
        alpha: 25,
        beta: 7,
        alphaDelta: 2.0,
        betaDelta: 0,
      );
      expect(s.evidence, closeTo(PolicyConstants.evidenceCap, 1e-9));
    });

    test('#278: the series of the issue, strong on medium at home', () {
      final right = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
      );
      final wrong = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.medium,
      );
      // J = right, F = wrong, in order.
      BeliefSnapshot run(String series) {
        var snap = const BeliefSnapshot(1, 1);
        for (final c in series.split('')) {
          final d = c == 'J' ? right : wrong;
          snap = applyEvidence(
            alpha: snap.alpha,
            beta: snap.beta,
            alphaDelta: d.alphaDelta,
            betaDelta: d.betaDelta,
          );
        }
        return snap;
      }

      expect(run('JJJ').mean, closeTo(0.84, 0.005));
      // #245: under the cap 0.59, and stuck at the ninth answer.
      expect(run('FFJFJJFJJJ').mean, closeTo(0.75, 0.005));
      expect(run('FFFFFFJJJJ').mean, closeTo(0.72, 0.005));
      expect(run('${'F' * 12}JJJJ').mean, closeTo(0.70, 0.005));
      // Volume alone gives no stamp.
      expect(run('JF' * 10).mean, closeTo(0.43, 0.005));
      expect(run('${'J' * 10}F').mean, closeTo(0.65, 0.005));
    });
  });

  group('mastery & stuck predicates', () {
    test('mean ≥ 0.8 AND evidence ≥ 5.75 → mastery condition met', () {
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(5, 1)), isTrue);
      // Just one signal short on mean.
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(4, 2)), isFalse);
      // Mean over the bar, short on evidence: (4, 1) was mastery at the old
      // bar of 4 (#276), and (4.5, 1) is one right answer on hard in the
      // lesson time.
      expect(
        meetsMasteryMeanAndEvidence(const BeliefSnapshot(4.5, 1)),
        isFalse,
      );
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(4, 1)), isFalse);
    });

    test('#276: one right answer on hard in the lesson time is not mastery '
        'from the prior; two are', () {
      final one = signalDeltas(
        kind: LoSignalKind.positive,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.hard,
        provenance: EvidenceProvenance.supervised,
      );
      // (4.5, 1): μ 0.82 but evidence 5.5 — at the old bar of 4, mastery.
      final after1 = applyEvidence(
        alpha: PolicyConstants.prior,
        beta: PolicyConstants.prior,
        alphaDelta: one.alphaDelta,
        betaDelta: one.betaDelta,
      );
      expect(after1.mean, greaterThan(PolicyConstants.masteryMeanThreshold));
      expect(meetsMasteryMeanAndEvidence(after1), isFalse);
      final after2 = applyEvidence(
        alpha: after1.alpha,
        beta: after1.beta,
        alphaDelta: one.alphaDelta,
        betaDelta: one.betaDelta,
      );
      expect(meetsMasteryMeanAndEvidence(after2), isTrue);
    });

    test('#278: a new LO takes three strong right answers on medium at home, '
        'two on hard', () {
      BeliefSnapshot rightAnswers(int n, QuestionDifficulty level) {
        final d = signalDeltas(
          kind: LoSignalKind.positive,
          strength: LoSignalStrength.strong,
          difficulty: level,
        );
        var snap = const BeliefSnapshot(1, 1);
        for (var i = 0; i < n; i++) {
          snap = applyEvidence(
            alpha: snap.alpha,
            beta: snap.beta,
            alphaDelta: d.alphaDelta,
            betaDelta: d.betaDelta,
          );
        }
        return snap;
      }

      // (4.4, 1): μ 0.81 on evidence 5.4 — the first answer shrank first.
      final two = rightAnswers(2, QuestionDifficulty.medium);
      expect(two.alpha, closeTo(4.4, 1e-9));
      expect(meetsMasteryMeanAndEvidence(two), isFalse);
      expect(
        meetsMasteryMeanAndEvidence(rightAnswers(3, QuestionDifficulty.medium)),
        isTrue,
      );
      expect(
        meetsMasteryMeanAndEvidence(rightAnswers(2, QuestionDifficulty.hard)),
        isTrue,
      );
    });

    test('#278 stuck: ≥ 6 own questions and mean < 0.6', () {
      expect(PolicyConstants.stuckOwnQuestionsMin, 6);
      expect(isStuck(const BeliefSnapshot(3, 7), ownQuestions: 6), isTrue);
      expect(isStuck(const BeliefSnapshot(3, 7), ownQuestions: 9), isTrue);
      // Tried too little, whatever the evidence: (3, 7) was stuck at the
      // old bar of α + β ≥ 10.
      expect(isStuck(const BeliefSnapshot(3, 7), ownQuestions: 5), isFalse);
      // At or above the stuck mean ceiling: on the upswing, keep probing.
      expect(isStuck(const BeliefSnapshot(7, 3), ownQuestions: 12), isFalse);
      expect(isStuck(const BeliefSnapshot(3, 2), ownQuestions: 12), isFalse);
    });

    test('#278: four wrong answers on hard in the lesson time are not yet '
        'stuck — the attempts rule asks a notch lower, and two questions are '
        'left there', () {
      final wrong = signalDeltas(
        kind: LoSignalKind.negative,
        strength: LoSignalStrength.strong,
        difficulty: QuestionDifficulty.hard,
        provenance: EvidenceProvenance.supervised,
      );
      var snap = const BeliefSnapshot(
        PolicyConstants.prior,
        PolicyConstants.prior,
      );
      for (var i = 0; i < 4; i++) {
        snap = applyEvidence(
          alpha: snap.alpha,
          beta: snap.beta,
          alphaDelta: wrong.alphaDelta,
          betaDelta: wrong.betaDelta,
        );
      }
      expect(snap.mean, lessThan(PolicyConstants.stuckMeanCeiling));
      expect(isStuck(snap, ownQuestions: 4), isFalse);
      expect(isStuck(snap, ownQuestions: 6), isTrue);
    });

    test('#278: no saturated branch — an LO at the old cap with μ 0.67 is '
        'not stuck, however often it was asked', () {
      // (12, 6) was stuck by the saturated branch (α + β ≥ 18, μ < 0.75).
      expect(isStuck(const BeliefSnapshot(12, 6), ownQuestions: 20), isFalse);
    });
  });

  group('#279 a pick weighs half; condition 4; the type rule', () {
    const medium = QuestionDifficulty.medium;
    const hard = QuestionDifficulty.hard;
    const easy = QuestionDifficulty.easy;
    final at = DateTime.utc(2026, 11, 1);

    LoBelief doc({
      bool atCalibration = true,
      DateTime? firstMasteredAt,
      int? right,
      int? nonMcq,
    }) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 5,
      beta: 1,
      lastUpdatedAt: at,
      lastPositiveAtCalibratedAt: atCalibration ? at : null,
      firstMasteredAt: firstMasteredAt,
      ownQuestionsRight: right,
      ownQuestionsRightNonMcq: nonMcq,
    );

    test('a positive of a pick weighs half — on the target and from the '
        'side; a negative and a neutral as before', () {
      expect(PolicyConstants.multipleChoicePositiveFactor, 0.5);
      for (final level in QuestionDifficulty.values) {
        final full = signalDeltas(
          kind: LoSignalKind.positive,
          strength: LoSignalStrength.strong,
          difficulty: level,
          provenance: EvidenceProvenance.supervised,
        );
        final pick = signalDeltas(
          kind: LoSignalKind.positive,
          strength: LoSignalStrength.strong,
          difficulty: level,
          provenance: EvidenceProvenance.supervised,
          multipleChoice: true,
        );
        expect(pick.alphaDelta, closeTo(full.alphaDelta * 0.5, 1e-12));
        // A strong pick weighs as a moderate answer.
        expect(
          pick.alphaDelta,
          closeTo(
            signalDeltas(
              kind: LoSignalKind.positive,
              strength: LoSignalStrength.moderate,
              difficulty: level,
              provenance: EvidenceProvenance.supervised,
            ).alphaDelta,
            1e-12,
          ),
        );
        final wrong = signalDeltas(
          kind: LoSignalKind.negative,
          strength: LoSignalStrength.moderate,
          difficulty: level,
          multipleChoice: true,
        );
        expect(
          wrong.betaDelta,
          PolicyConstants.negativeDifficultyMultiplier(level),
        );
      }
      expect(
        crossSubgoalSignalDeltas(
          kind: LoSignalKind.positive,
          strength: LoSignalStrength.strong,
          multipleChoice: true,
        ).alphaDelta,
        closeTo(1.0, 1e-12),
      );
      final neutral = signalDeltas(
        kind: LoSignalKind.neutral,
        strength: LoSignalStrength.strong,
        difficulty: medium,
        multipleChoice: true,
      );
      expect((neutral.alphaDelta, neutral.betaDelta), (0.0, 0.0));
    });

    test('condition 4: two right own questions, one of them no pick; a '
        'missing count reads 0', () {
      bool meets(int? right, int? nonMcq) => meetsOwnQuestionsCondition(
        ownQuestionsRight: right,
        ownQuestionsRightNonMcq: nonMcq,
      );
      expect(meets(2, 1), isTrue);
      expect(meets(5, 3), isTrue);
      expect(meets(1, 1), isFalse);
      expect(meets(4, 0), isFalse);
      expect(meets(null, null), isFalse);
    });

    test('mastered now: the four conditions, the fourth only without a '
        'stamp — a stamp that is there stays', () {
      const over = BeliefSnapshot(5, 1);
      const under = BeliefSnapshot(4, 1.2);
      expect(isMastered(over, doc(right: 2, nonMcq: 1)), isTrue);
      expect(isMastered(over, doc(right: 3, nonMcq: 0)), isFalse);
      expect(isMastered(over, doc(right: 1, nonMcq: 1)), isFalse);
      expect(isMastered(under, doc(right: 2, nonMcq: 1)), isFalse);
      expect(
        isMastered(over, doc(atCalibration: false, right: 2, nonMcq: 1)),
        isFalse,
      );
      expect(isMastered(over, null), isFalse);
      // Stamped, with or without counts: conditions 1–3 decide.
      expect(isMastered(over, doc(firstMasteredAt: at)), isTrue);
      expect(isMastered(over, doc(firstMasteredAt: at, right: 0)), isTrue);
      expect(isMastered(under, doc(firstMasteredAt: at)), isFalse);
      // An old doc without counts that met 1–3 at its last write: the
      // reading of everMastered, a stamp an old build did not write.
      expect(isMastered(over, doc()), isTrue);
      // A 1.1 doc keeps counts: the fourth condition holds it.
      expect(isMastered(over, doc(right: 0, nonMcq: 0)), isFalse);
    });

    test('picks alone: with forgetting a run of right picks at home stops '
        'at evidence 4 on easy and 5.33 on medium — under 5.75 — and only '
        'on hard gets over the bar', () {
      expect(picksAloneCanMaster(easy), isFalse);
      expect(picksAloneCanMaster(medium), isFalse);
      expect(picksAloneCanMaster(hard), isTrue);
      var snap = const BeliefSnapshot(1, 1);
      for (var i = 0; i < 60; i++) {
        final d = signalDeltas(
          kind: LoSignalKind.positive,
          strength: LoSignalStrength.strong,
          difficulty: medium,
          multipleChoice: true,
        );
        snap = applyEvidence(
          alpha: snap.alpha,
          beta: snap.beta,
          alphaDelta: d.alphaDelta,
          betaDelta: d.betaDelta,
        );
      }
      expect(snap.evidence, closeTo(2 + 1.0 / 0.3, 1e-6));
      expect(meetsMasteryMeanAndEvidence(snap), isFalse);
    });

    test('one right answer, a pick or not', () {
      // (3.5, 1) on hard: another type takes it to (5.55, 1), a pick to
      // (4.15, 1), evidence 5.15.
      const snap = BeliefSnapshot(3.5, 1);
      expect(
        oneRightAnswerMeetsMeanAndEvidence(snap: snap, calibration: hard),
        isTrue,
      );
      expect(
        oneRightAnswerMeetsMeanAndEvidence(
          snap: snap,
          calibration: hard,
          multipleChoice: true,
        ),
        isFalse,
      );
    });

    group('the type rule', () {
      bool needs(
        LoBelief? b, {
        BeliefSnapshot snap = const BeliefSnapshot(2, 1.5),
        QuestionDifficulty calibration = medium,
      }) =>
          needsNonMcqQuestion(snap: snap, belief: b, calibration: calibration);

      test('before the first right own question a pick is the way in', () {
        expect(needs(null), isFalse);
        expect(needs(doc(right: 0, nonMcq: 0)), isFalse);
        expect(needs(doc()), isFalse); // a doc from before 1.1
        expect(needs(doc(right: 0, nonMcq: 0), calibration: easy), isFalse);
      });

      test('1. the right non-pick is missing: at any level', () {
        for (final level in QuestionDifficulty.values) {
          expect(needs(doc(right: 1, nonMcq: 0), calibration: level), isTrue);
          expect(needs(doc(right: 4, nonMcq: 0), calibration: level), isTrue);
        }
      });

      test('2. picks cannot get there: on easy and medium, also for a '
          'stamped LO that dipped under the bar', () {
        expect(needs(doc(right: 2, nonMcq: 1)), isTrue);
        expect(needs(doc(right: 2, nonMcq: 1), calibration: easy), isTrue);
        expect(needs(doc(firstMasteredAt: at)), isTrue);
        // On hard, far from the bar, a pick still helps.
        expect(needs(doc(right: 2, nonMcq: 1), calibration: hard), isFalse);
        expect(needs(doc(firstMasteredAt: at), calibration: hard), isFalse);
      });

      test('3. on hard, the next right answer decides: no pick when only '
          'another type would master it', () {
        const deciding = BeliefSnapshot(3.5, 1);
        expect(
          needs(doc(right: 2, nonMcq: 1), snap: deciding, calibration: hard),
          isTrue,
        );
        // Where a pick would master it too, a pick is fine.
        const close = BeliefSnapshot(4.6, 1);
        expect(
          oneRightAnswerMeetsMeanAndEvidence(
            snap: close,
            calibration: hard,
            multipleChoice: true,
          ),
          isTrue,
        );
        expect(
          needs(doc(right: 2, nonMcq: 1), snap: close, calibration: hard),
          isFalse,
        );
      });
    });
  });

  group('#275 isThinStamp', () {
    LoBelief doc({DateTime? stamp, int? right, int? nonMcq}) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 4,
      beta: 1,
      lastUpdatedAt: DateTime.utc(2026, 10, 1),
      lastPositiveAtCalibratedAt: DateTime.utc(2026, 10, 1),
      firstMasteredAt: stamp,
      ownQuestionsRight: right,
      ownQuestionsRightNonMcq: nonMcq,
    );
    final stamp = DateTime.utc(2026, 10, 1);

    test('a stamp on fewer than two right own questions, by the counts', () {
      expect(isThinStamp(doc(stamp: stamp, right: 0, nonMcq: 0)), isTrue);
      expect(isThinStamp(doc(stamp: stamp, right: 1, nonMcq: 0)), isTrue);
      // Two picks are not thin by this rule: "minder dan twee juiste eigen
      // vragen", the non-pick count plays no part.
      expect(isThinStamp(doc(stamp: stamp, right: 2, nonMcq: 0)), isFalse);
      expect(isThinStamp(doc(stamp: stamp, right: 3, nonMcq: 1)), isFalse);
    });

    test('no stamp, or no counts on the doc (a stamp from before they were '
        'kept, until the release fills them): not thin', () {
      expect(isThinStamp(doc(right: 0, nonMcq: 0)), isFalse);
      expect(isThinStamp(doc(stamp: stamp)), isFalse);
    });
  });
}
