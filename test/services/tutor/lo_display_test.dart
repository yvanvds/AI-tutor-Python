// #230, #325 — the segments of the student's subgoal bar: the right answers
// an LO still needs (`rightAnswersToGo`), the fill that goes with them
// (`loSegmentFill`), the session's readings and why a number went up
// (`nextLoDisplayReading`), and the bar's counts and share. The conductor's
// side — which LOs get a segment, the level each is counted at, what a turn
// did to an LO, the marker — is in conductor_test.dart.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

const _prior = BeliefSnapshot(PolicyConstants.prior, PolicyConstants.prior);
const _easy = QuestionDifficulty.easy;
const _medium = QuestionDifficulty.medium;
const _hard = QuestionDifficulty.hard;

final _at = DateTime.utc(2026, 10, 1);

/// [snap] after one right answer at [level]: strong unless [strength] says
/// otherwise, from home unless [provenance] does.
BeliefSnapshot _afterRight(
  BeliefSnapshot snap,
  QuestionDifficulty level, {
  LoSignalStrength strength = LoSignalStrength.strong,
  EvidenceProvenance provenance = EvidenceProvenance.home,
}) {
  final d = signalDeltas(
    kind: LoSignalKind.positive,
    strength: strength,
    difficulty: level,
    provenance: provenance,
  );
  return applyEvidence(
    alpha: snap.alpha,
    beta: snap.beta,
    alphaDelta: d.alphaDelta,
    betaDelta: d.betaDelta,
  );
}

/// [snap] after one wrong answer at [level].
BeliefSnapshot _afterWrong(BeliefSnapshot snap, QuestionDifficulty level) {
  final d = signalDeltas(
    kind: LoSignalKind.negative,
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

/// The doc of an LO at [snap]: by default one right own question, no pick,
/// that set [atCalibration].
LoBelief _doc(
  BeliefSnapshot snap, {
  bool atCalibration = true,
  DateTime? firstMasteredAt,
  int ownQuestions = 1,
  int? right = 1,
  int? nonMcq = 1,
}) => LoBelief(
  subgoalId: 's1',
  loId: 'lo-a',
  alpha: snap.alpha,
  beta: snap.beta,
  lastUpdatedAt: _at,
  lastPositiveAtCalibratedAt: atCalibration ? _at : null,
  firstMasteredAt: firstMasteredAt,
  ownQuestions: ownQuestions,
  ownQuestionsRight: right,
  ownQuestionsRightNonMcq: nonMcq,
);

/// The right answers to go for [snap] with its doc as in [_doc].
int _toGo(
  BeliefSnapshot snap, {
  QuestionDifficulty calibration = _hard,
  QuestionDifficulty? askedAt,
  bool atCalibration = true,
  DateTime? firstMasteredAt,
  int ownQuestions = 1,
  int? right = 1,
  int? nonMcq = 1,
  bool noDoc = false,
}) => rightAnswersToGo(
  snap: snap,
  belief: noDoc
      ? null
      : _doc(
          snap,
          atCalibration: atCalibration,
          firstMasteredAt: firstMasteredAt,
          ownQuestions: ownQuestions,
          right: right,
          nonMcq: nonMcq,
        ),
  calibration: calibration,
  askedAt: askedAt,
);

void main() {
  group('the right answers to go, from the belief', () {
    test('from the prior: two on hard, three on medium, eight on easy — '
        'forgetting shrinks each answer before the next lands (#278)', () {
      expect(_toGo(_prior, noDoc: true), 2);
      expect(_toGo(_prior, calibration: _medium, noDoc: true), 3);
      expect(_toGo(_prior, calibration: _easy, noDoc: true), 8);
    });

    test('climbing from a low mean counts down: every strong right answer '
        'at the level asked takes one off, to 0 when mastered', () {
      for (final level in QuestionDifficulty.values) {
        // μ 0.19, the LO of the issue: well under 0.6 after six oefeningen.
        var snap = const BeliefSnapshot(1.5, 6.5);
        var right = 0;
        var toGo = _toGo(
          snap,
          calibration: level,
          atCalibration: false,
          right: right,
          nonMcq: right,
        );
        expect(toGo, greaterThan(2), reason: '$level');
        while (toGo > 0) {
          snap = _afterRight(snap, level);
          right += 1;
          final next = _toGo(
            snap,
            calibration: level,
            right: right,
            nonMcq: right,
          );
          expect(next, toGo - 1, reason: '$level after $right right');
          toGo = next;
        }
        expect(isMastered(snap, _doc(snap, right: right, nonMcq: right)), true);
      }
    });

    test('one right answer away is the old half: after the first right '
        'answer on hard', () {
      final once = _afterRight(_prior, _hard);
      expect(once.mean, closeTo(3.8 / 4.8, 1e-9));
      expect(_toGo(once), 1);
    });

    test('the same belief needs more right answers at a lower level', () {
      // μ 0.71: one strong right answer takes it to 0.81 on hard (+2.8),
      // 0.75 on easy (+1.2), forgetting first (#278).
      const snap = BeliefSnapshot(3.7, 1.5);
      expect(_toGo(snap), 1);
      expect(_toGo(snap, calibration: _easy), greaterThan(1));
    });

    test('counted at the level the LO is asked at: a notch lower, the first '
        'right answer weighs less and cannot give condition 3', () {
      const snap = BeliefSnapshot(5, 1);
      expect(_toGo(snap, calibration: _medium, atCalibration: false), 1);
      expect(
        _toGo(snap, calibration: _medium, askedAt: _easy, atCalibration: false),
        2,
      );
      // With condition 3 already met, only the weight differs.
      const low = BeliefSnapshot(2, 2);
      expect(
        _toGo(low, calibration: _hard, askedAt: _medium),
        greaterThanOrEqualTo(_toGo(low, calibration: _hard)),
      );
    });

    test('a belief over the bar without a right answer at the student\'s '
        'level needs that answer', () {
      const snap = BeliefSnapshot(5, 1);
      expect(meetsMasteryMeanAndEvidence(snap), isTrue);
      expect(_toGo(snap, atCalibration: false), 1);
      expect(_toGo(snap, right: 2), 0);
    });

    test('#279: the right own questions count — one more when one is '
        'missing, or the non-pick, two without any', () {
      const snap = BeliefSnapshot(5, 1);
      expect(_toGo(snap, right: 1, nonMcq: 1), 1);
      expect(_toGo(snap, right: 1, nonMcq: 0), 1);
      expect(_toGo(snap, right: 3, nonMcq: 0), 1);
      expect(_toGo(snap, right: 2, nonMcq: 1), 0);
      expect(_toGo(snap, atCalibration: false, right: 0, nonMcq: 0), 2);
      // A doc without the counts reads 0 ...
      expect(_toGo(snap, atCalibration: false, right: null, nonMcq: null), 2);
      // ... but one over the bar, right at calibration, is a stamp an old
      // build gave and did not write: mastered, as before 1.1.
      expect(_toGo(snap, right: null, nonMcq: null), 0);
    });

    test('a stamp waives condition 4, as in isMastered: mastered again on '
        'conditions 1–3', () {
      const snap = BeliefSnapshot(5, 1);
      expect(
        _toGo(snap, right: 0, nonMcq: 0, firstMasteredAt: DateTime.utc(2026)),
        0,
      );
    });

    test('a wrong answer after mastery takes it down; the stamp stays on the '
        'doc and is no reason to show it full', () {
      final stamped = DateTime.utc(2026, 9, 1);
      final mastered = _afterRight(_afterRight(_prior, _hard), _hard);
      expect(_toGo(mastered, right: 2, nonMcq: 2, firstMasteredAt: stamped), 0);
      final dropped = _afterWrong(mastered, _hard);
      expect(
        _toGo(dropped, right: 2, nonMcq: 2, firstMasteredAt: stamped),
        greaterThan(0),
      );
      // Mastered once, fallen far since.
      expect(
        _toGo(const BeliefSnapshot(1.5, 4), firstMasteredAt: stamped),
        greaterThan(2),
      );
    });

    test('stuck is not full: it shows the right answers it still needs', () {
      const low = BeliefSnapshot(2.4, 5);
      expect(isStuck(low, ownQuestions: 6), isTrue);
      expect(
        _toGo(low, atCalibration: false, ownQuestions: 6, right: 0, nonMcq: 0),
        greaterThan(2),
      );
    });

    test('a strong right answer at the level asked never raises the count, '
        'nor does one in the lesson time', () {
      for (final level in QuestionDifficulty.values) {
        for (var a = 1.0; a < 12; a += 0.5) {
          for (var b = 1.0; b < 12; b += 0.5) {
            final snap = BeliefSnapshot(a, b);
            final before = _toGo(snap, calibration: level);
            for (final where in EvidenceProvenance.values) {
              final after = _toGo(
                _afterRight(snap, level, provenance: where),
                calibration: level,
                right: 2,
                nonMcq: 2,
              );
              expect(
                after,
                lessThanOrEqualTo(before),
                reason: '($a, $b) on $level, ${where.name}',
              );
            }
          }
        }
      }
    });

    test('a light right answer can: forgetting takes more than it adds — '
        'the reason the readings never let the count rise without a cause', () {
      // One right answer away on medium (it lands on evidence 5.75). A
      // right follow-up weighs 0.5 at medium (§6.2): it forgets 0.75 of α.
      const snap = BeliefSnapshot(3.5, 1);
      expect(_toGo(snap, calibration: _medium, right: 2), 1);
      final followUp = _afterRight(
        snap,
        _medium,
        strength: LoSignalStrength.weak,
      );
      expect(followUp.alpha, closeTo(3.25, 1e-9));
      expect(_toGo(followUp, calibration: _medium, right: 2), 2);
    });
  });

  group('the fill', () {
    test('a new LO needs 2 right answers on hard, 3 on medium, 8 on easy', () {
      expect(newLoRightAnswersToGo(_hard), 2);
      expect(newLoRightAnswersToGo(_medium), 3);
      expect(newLoRightAnswersToGo(_easy), 8);
    });

    test('full at 0, empty where a new LO starts: every right answer on the '
        'way fills a step', () {
      // Medium: 3, 2, 1, 0 to go.
      expect(loSegmentFill(3, newLoToGo: 3), 0.0);
      expect(loSegmentFill(2, newLoToGo: 3), closeTo(1 / 3, 1e-9));
      expect(loSegmentFill(1, newLoToGo: 3), closeTo(2 / 3, 1e-9));
      expect(loSegmentFill(0, newLoToGo: 3), 1.0);
      // Hard: a new LO is 2 away, so it starts empty too.
      expect(loSegmentFill(2, newLoToGo: 2), 0.0);
      expect(loSegmentFill(1, newLoToGo: 2), 0.5);
      // Further than a new LO — after wrong answers — is empty, not less.
      expect(loSegmentFill(9, newLoToGo: 3), 0.0);
      // Easy: an eighth per right answer.
      expect(loSegmentFill(4, newLoToGo: 8), 0.5);
    });
  });

  group('the readings over a session', () {
    LoDisplayReading read(
      LoDisplayReading? previous,
      int toGo, {
      QuestionDifficulty askedAt = _medium,
      QuestionDifficulty calibration = _medium,
      LoDisplayRise? turn,
    }) => nextLoDisplayReading(
      previous: previous,
      toGo: toGo,
      askedAt: askedAt,
      calibration: calibration,
      turnRise: turn,
    );

    test('the first reading follows the belief, without a reason', () {
      final r = read(null, 4);
      expect(r.toGo, 4);
      expect(r.rose, isNull);
    });

    test('down always follows the belief, and clears the reason', () {
      final up = read(read(null, 1), 3, turn: LoDisplayRise.notRight);
      expect(up.rose, LoDisplayRise.notRight);
      final down = read(up, 2);
      expect(down.toGo, 2);
      expect(down.rose, isNull);
    });

    test('a full segment drops after a wrong answer on it', () {
      final r = read(read(null, 0), 1, turn: LoDisplayRise.notRight);
      expect(r.toGo, 1);
      expect(r.rose, LoDisplayRise.notRight);
    });

    test('up after a negative from a question about another LO', () {
      final r = read(read(null, 1), 2, turn: LoDisplayRise.otherQuestion);
      expect(r.toGo, 2);
      expect(r.rose, LoDisplayRise.otherQuestion);
    });

    test('up at a lower level: the student\'s, or a notch drop on the LO', () {
      final demoted = read(
        read(null, 2, askedAt: _hard, calibration: _hard),
        3,
      );
      expect(demoted.toGo, 3);
      expect(demoted.rose, LoDisplayRise.lowerLevel);

      final dropped = read(read(null, 2), 3, askedAt: _easy);
      expect(dropped.toGo, 3);
      expect(dropped.rose, LoDisplayRise.lowerLevel);
    });

    test('the turn\'s reason goes before the level', () {
      final r = read(
        read(null, 1),
        3,
        askedAt: _easy,
        calibration: _easy,
        turn: LoDisplayRise.notRight,
      );
      expect(r.rose, LoDisplayRise.notRight);
    });

    test('without a reason the number does not go up: an answer that is not '
        'wrong never sets it back', () {
      final r = read(read(null, 1), 2);
      expect(r.toGo, 1);
      expect(r.rose, isNull);
      // ... and comes down with the belief once it is under the reading.
      expect(read(r, 1).toGo, 1);
      expect(read(r, 0).toGo, 0);
    });

    test('the reason stays while the number does', () {
      final up = read(read(null, 1), 2, turn: LoDisplayRise.otherQuestion);
      final again = read(up, 2);
      expect(again.rose, LoDisplayRise.otherQuestion);
      final held = read(up, 3);
      expect(held.toGo, 2);
      expect(held.rose, LoDisplayRise.otherQuestion);
    });
  });

  group('the bar', () {
    const bar = SubgoalLoDisplay(
      subgoalId: 's1',
      los: [
        LoDisplayEntry(loId: 'a', toGo: 0, newLoToGo: 3, demonstrated: true),
        LoDisplayEntry(loId: 'b', toGo: 1, newLoToGo: 3, demonstrated: true),
        LoDisplayEntry(loId: 'c', toGo: 2, newLoToGo: 3),
        LoDisplayEntry(loId: 'd', toGo: 3, newLoToGo: 3),
        LoDisplayEntry(loId: 'e', toGo: 5, newLoToGo: 3),
      ],
    );

    test('counts its mastered segments, the answers to go and the share '
        'they fill', () {
      expect(bar.masteredCount, 1);
      expect(bar.toGoTotal, 11);
      expect(bar.fraction, closeTo((1 + 2 / 3 + 1 / 3) / 5, 1e-9));
      expect(const SubgoalLoDisplay(subgoalId: 's1', los: []).fraction, 0.0);
    });

    test('two readings with the same segments and marker are equal', () {
      expect(SubgoalLoDisplay(subgoalId: 's1', los: [...bar.los]), equals(bar));
      expect(
        SubgoalLoDisplay(subgoalId: 's2', los: [...bar.los]),
        isNot(equals(bar)),
      );
      expect(bar.withCurrent('c'), isNot(equals(bar)));
      expect(bar.withCurrent('c').currentLoId, 'c');
      expect(bar.withCurrent('c').withCurrent(null), equals(bar));
    });
  });
}
