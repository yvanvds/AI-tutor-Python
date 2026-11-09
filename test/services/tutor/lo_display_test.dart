// #230 — the segments of the student's subgoal bar: the state of one LO's
// segment from its belief (`loDisplayStateOf`), the session's hold on it
// (`heldLoDisplayState`), and the bar's counts and share. The conductor's
// side — which LOs get a segment, when it publishes, what counts as asked —
// is in conductor_test.dart.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

const _prior = BeliefSnapshot(PolicyConstants.prior, PolicyConstants.prior);

/// [snap] after one strong right answer at [level], from home.
BeliefSnapshot _afterRight(BeliefSnapshot snap, QuestionDifficulty level) {
  final d = signalDeltas(
    kind: LoSignalKind.positive,
    strength: LoSignalStrength.strong,
    difficulty: level,
  );
  return applyEvidence(
    alpha: snap.alpha,
    beta: snap.beta,
    alphaDelta: d.alphaDelta,
    betaDelta: d.betaDelta,
  );
}

/// The segment of [snap]. [right] and [nonMcq]: the doc's right own
/// questions, and those of them no multiple choice (#279) — by default
/// one, the answer that set [atCalibration].
LoDisplayState _state(
  BeliefSnapshot snap, {
  QuestionDifficulty calibration = QuestionDifficulty.hard,
  bool atCalibration = true,
  DateTime? firstMasteredAt,
  int ownQuestions = 0,
  int? right = 1,
  int? nonMcq = 1,
}) => loDisplayStateOf(
  snap: snap,
  lastPositiveAtCalibratedAt: atCalibration ? DateTime.utc(2026, 10, 1) : null,
  firstMasteredAt: firstMasteredAt,
  calibration: calibration,
  ownQuestions: ownQuestions,
  ownQuestionsRight: right,
  ownQuestionsRightNonMcq: nonMcq,
);

void main() {
  group('the state of a segment from the belief', () {
    test('the prior is empty: one right answer on hard leaves μ at 0.79 and '
        'the evidence under 5.75', () {
      expect(_state(_prior, atCalibration: false), LoDisplayState.empty);
      expect(
        oneRightAnswerMasters(
          snap: _prior,
          calibration: QuestionDifficulty.hard,
          ownQuestionsRight: 0,
        ),
        isFalse,
      );
    });

    test('the first right answer on hard gives half', () {
      final once = _afterRight(_prior, QuestionDifficulty.hard);
      expect(once.mean, closeTo(3.8 / 4.8, 1e-9));
      expect(meetsMasteryMeanAndEvidence(once), isFalse);

      expect(_state(once), LoDisplayState.half);
    });

    test('#278: on medium at home it takes two right answers for half, on '
        'easy seven: forgetting shrinks each answer before the next lands', () {
      const medium = QuestionDifficulty.medium;
      final once = _afterRight(_prior, medium);
      // (3, 1); a second right answer takes it to (4.4, 1), evidence 5.4.
      expect(_state(once, calibration: medium), LoDisplayState.empty);
      expect(
        _state(_afterRight(once, medium), calibration: medium, right: 2),
        LoDisplayState.half,
      );

      // On easy a strong right answer weighs 1.2 at home: α climbs toward
      // 1 + 1.2 / 0.3 = 5, and the evidence bar of 5.75 needs α ≥ 4.75.
      const easy = QuestionDifficulty.easy;
      var snap = _prior;
      for (var i = 0; i < 6; i++) {
        snap = _afterRight(snap, easy);
      }
      expect(
        _state(snap, calibration: easy, right: 6, nonMcq: 6),
        LoDisplayState.empty,
      );
      expect(
        _state(_afterRight(snap, easy), calibration: easy, right: 7, nonMcq: 7),
        LoDisplayState.half,
      );
    });

    test('the right answer is weighed at the student\'s calibration: the '
        'same belief is half on hard and empty on easy', () {
      // μ 0.71: one strong right answer takes it to 0.81 on hard (+2.8),
      // 0.75 on easy (+1.2), forgetting first (#278).
      const snap = BeliefSnapshot(3.7, 1.5);
      expect(_state(snap), LoDisplayState.half);
      expect(
        _state(snap, calibration: QuestionDifficulty.easy),
        LoDisplayState.empty,
      );
    });

    test('a belief over the bar without a right answer at the student\'s '
        'level is half: that answer is the one missing condition', () {
      const snap = BeliefSnapshot(5, 1);
      expect(meetsMasteryMeanAndEvidence(snap), isTrue);
      expect(_state(snap, atCalibration: false), LoDisplayState.half);
      expect(_state(snap, right: 2), LoDisplayState.full);
    });

    test('mastered is full', () {
      final twice = _afterRight(
        _afterRight(_prior, QuestionDifficulty.hard),
        QuestionDifficulty.hard,
      );
      expect(_state(twice, right: 2, nonMcq: 2), LoDisplayState.full);
    });

    test('#279: over the bar on one right own question, or on picks alone, '
        'is half — the next right answer is the stamp, if it is no pick — '
        'and full once two are right, one of them no pick', () {
      const snap = BeliefSnapshot(5, 1);
      expect(_state(snap, right: 1, nonMcq: 1), LoDisplayState.half);
      expect(_state(snap, right: 1, nonMcq: 0), LoDisplayState.half);
      expect(_state(snap, right: 3, nonMcq: 0), LoDisplayState.half);
      expect(_state(snap, right: 2, nonMcq: 1), LoDisplayState.full);
    });

    test('#279: without a right own question one answer cannot master it, '
        'however high side signals took the belief; a doc without the '
        'counts reads 0', () {
      const snap = BeliefSnapshot(5, 1);
      expect(
        _state(snap, atCalibration: false, right: 0, nonMcq: 0),
        LoDisplayState.empty,
      );
      expect(
        _state(snap, atCalibration: false, right: null, nonMcq: null),
        LoDisplayState.empty,
      );
      expect(
        oneRightAnswerMasters(
          snap: snap,
          calibration: QuestionDifficulty.hard,
          ownQuestionsRight: null,
        ),
        isFalse,
      );
      // A doc without the counts over the bar, right at calibration: a stamp
      // an old build gave and did not write — full, as before 1.1.
      expect(_state(snap, right: null, nonMcq: null), LoDisplayState.full);
      // A stamp that is there stays full, counts or not.
      expect(
        _state(
          snap,
          right: null,
          nonMcq: null,
          firstMasteredAt: DateTime.utc(2026, 9, 1),
        ),
        LoDisplayState.full,
      );
    });

    test('stuck is full: six own questions and μ under 0.6 (#278)', () {
      const low = BeliefSnapshot(2.4, 5);
      expect(isStuck(low, ownQuestions: 6), isTrue);
      expect(
        _state(low, atCalibration: false, ownQuestions: 6),
        LoDisplayState.full,
      );
      // Five own questions: not yet stuck, and far from mastery.
      expect(
        _state(low, atCalibration: false, ownQuestions: 5),
        LoDisplayState.empty,
      );
      // The saturated branch is gone: evidence 19 and μ 0.68 is no longer
      // stuck, and one right answer on hard does not master it either.
      expect(
        _state(const BeliefSnapshot(13, 6), ownQuestions: 20),
        LoDisplayState.empty,
      );
    });

    test('an LO ever mastered is full, however far it fell since', () {
      expect(
        _state(
          const BeliefSnapshot(1.5, 4),
          firstMasteredAt: DateTime.utc(2026, 9, 1),
        ),
        LoDisplayState.full,
      );
    });
  });

  group('the hold over a session', () {
    LoDisplayState held(
      LoDisplayState? before,
      LoDisplayState now, {
      bool asked = false,
    }) => heldLoDisplayState(held: before, fresh: now, askedAndNotRight: asked);

    test('the first reading follows the belief', () {
      for (final s in LoDisplayState.values) {
        expect(held(null, s), s);
      }
    });

    test('a negative from the side leaves half', () {
      expect(
        held(LoDisplayState.half, LoDisplayState.empty),
        LoDisplayState.half,
      );
    });

    test('a not-right answer on the question itself empties half', () {
      expect(
        held(LoDisplayState.half, LoDisplayState.empty, asked: true),
        LoDisplayState.empty,
      );
    });

    test('a not-right answer that keeps the LO one answer away keeps half', () {
      expect(
        held(LoDisplayState.half, LoDisplayState.half, asked: true),
        LoDisplayState.half,
      );
    });

    test('full stays full after a later wrong answer', () {
      for (final now in LoDisplayState.values) {
        expect(held(LoDisplayState.full, now), LoDisplayState.full);
        expect(
          held(LoDisplayState.full, now, asked: true),
          LoDisplayState.full,
        );
      }
    });

    test('up is always allowed', () {
      expect(
        held(LoDisplayState.empty, LoDisplayState.half),
        LoDisplayState.half,
      );
      expect(
        held(LoDisplayState.empty, LoDisplayState.full),
        LoDisplayState.full,
      );
      expect(
        held(LoDisplayState.half, LoDisplayState.full, asked: true),
        LoDisplayState.full,
      );
    });
  });

  group('the bar', () {
    const bar = SubgoalLoDisplay(
      subgoalId: 's1',
      los: [
        LoDisplayEntry(loId: 'a', state: LoDisplayState.full),
        LoDisplayEntry(loId: 'b', state: LoDisplayState.full),
        LoDisplayEntry(loId: 'c', state: LoDisplayState.half),
        LoDisplayEntry(loId: 'd', state: LoDisplayState.empty),
        LoDisplayEntry(loId: 'e', state: LoDisplayState.empty),
      ],
    );

    test('counts its segments and the share they fill', () {
      expect(bar.fullCount, 2);
      expect(bar.halfCount, 1);
      expect(bar.emptyCount, 2);
      expect(bar.fraction, closeTo(2.5 / 5, 1e-9));
      expect(const SubgoalLoDisplay(subgoalId: 's1', los: []).fraction, 0.0);
    });

    test('two readings with the same segments are equal', () {
      expect(SubgoalLoDisplay(subgoalId: 's1', los: [...bar.los]), equals(bar));
      expect(
        SubgoalLoDisplay(subgoalId: 's2', los: [...bar.los]),
        isNot(equals(bar)),
      );
    });
  });
}
