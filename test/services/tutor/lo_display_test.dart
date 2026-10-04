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

LoDisplayState _state(
  BeliefSnapshot snap, {
  QuestionDifficulty calibration = QuestionDifficulty.hard,
  bool atCalibration = true,
  DateTime? firstMasteredAt,
}) => loDisplayStateOf(
  snap: snap,
  lastPositiveAtCalibratedAt: atCalibration ? DateTime.utc(2026, 10, 1) : null,
  firstMasteredAt: firstMasteredAt,
  calibration: calibration,
);

void main() {
  group('the state of a segment from the belief', () {
    test('the prior is empty: one right answer on hard leaves μ at 0.79', () {
      expect(_state(_prior, atCalibration: false), LoDisplayState.empty);
      expect(
        oneRightAnswerMasters(
          snap: _prior,
          calibration: QuestionDifficulty.hard,
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

    test('on medium the first right answer gives half too; on easy it takes '
        'two', () {
      const medium = QuestionDifficulty.medium;
      expect(
        _state(_afterRight(_prior, medium), calibration: medium),
        LoDisplayState.half,
      );

      const easy = QuestionDifficulty.easy;
      final once = _afterRight(_prior, easy);
      expect(_state(once, calibration: easy), LoDisplayState.empty);
      expect(
        _state(_afterRight(once, easy), calibration: easy),
        LoDisplayState.half,
      );
    });

    test('the right answer is weighed at the student\'s calibration: the '
        'same belief is half on hard and empty on easy', () {
      // μ 0.71: one strong right answer takes it to 0.84 on hard (+2.8),
      // 0.79 on easy (+1.2).
      const snap = BeliefSnapshot(3.7, 1.5);
      expect(_state(snap), LoDisplayState.half);
      expect(
        _state(snap, calibration: QuestionDifficulty.easy),
        LoDisplayState.empty,
      );
    });

    test('a belief over the bar without a right answer at the student\'s '
        'level is half: that answer is the one missing condition', () {
      const snap = BeliefSnapshot(4.5, 1);
      expect(meetsMasteryMeanAndEvidence(snap), isTrue);
      expect(_state(snap, atCalibration: false), LoDisplayState.half);
      expect(_state(snap), LoDisplayState.full);
    });

    test('mastered is full', () {
      final twice = _afterRight(
        _afterRight(_prior, QuestionDifficulty.hard),
        QuestionDifficulty.hard,
      );
      expect(_state(twice), LoDisplayState.full);
    });

    test('stuck is full', () {
      // Classic: evidence 8, μ 0.49.
      const classic = BeliefSnapshot(3.9, 4.1);
      expect(isStuck(classic), isTrue);
      expect(_state(classic, atCalibration: false), LoDisplayState.full);
      // Saturated: evidence 19, μ 0.68.
      const saturated = BeliefSnapshot(13, 6);
      expect(isStuck(saturated), isTrue);
      expect(_state(saturated), LoDisplayState.full);
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
