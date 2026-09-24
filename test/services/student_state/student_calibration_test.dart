// Issue #187 — "the student's recent work at their level is good", the gate
// of the recheck slot's near-goal rule (CONDUCTOR_POLICY §2.6).
//
// The calibration window is weighted the way μ is since #169: a correct
// answer by the positive difficulty factor, anything else by the negative
// one, so the same 0.75 bar means ~56% raw at hard and ~88% at easy. Raw
// accuracy would never clear 0.75 at hard for a student the ladder parks
// there on purpose (40–75%), which is what hid every fossil in the first
// report round.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

StudentCalibration _window({
  required int correct,
  required int other,
  QuestionDifficulty at = QuestionDifficulty.medium,
  AnswerQuality otherQuality = AnswerQuality.wrong,
}) {
  final t = DateTime.utc(2026, 9, 18, 9);
  return StudentCalibration(
    difficulty: at,
    recentAnswers: [
      for (var i = 0; i < correct; i++)
        CalibrationAnswer(
          quality: AnswerQuality.correct,
          difficulty: at,
          at: t,
        ),
      for (var i = 0; i < other; i++)
        CalibrationAnswer(quality: otherQuality, difficulty: at, at: t),
    ],
  );
}

void main() {
  group('StudentCalibration.levelWeightedAccuracy (#187)', () {
    test('is null until the window is full', () {
      expect(StudentCalibration.fresh().levelWeightedAccuracy, isNull);
      expect(
        _window(
          correct: PolicyConstants.calibrationWindow - 1,
          other: 0,
        ).levelWeightedAccuracy,
        isNull,
      );
      expect(
        _window(
          correct: PolicyConstants.calibrationWindow,
          other: 0,
        ).levelWeightedAccuracy,
        1.0,
      );
    });

    test('at medium it is the plain share of correct answers', () {
      expect(
        _window(correct: 7, other: 3).levelWeightedAccuracy,
        closeTo(0.7, 1e-9),
      );
    });

    test('at hard, 6 of 10 reads as 0.78: a right answer counts 1.4, a '
        'wrong one 0.6', () {
      final acc = _window(
        correct: 6,
        other: 4,
        at: QuestionDifficulty.hard,
      ).levelWeightedAccuracy!;
      expect(acc, closeTo(6 * 1.4 / (6 * 1.4 + 4 * 0.6), 1e-9));
      expect(acc, greaterThanOrEqualTo(PolicyConstants.recheckRecentAccuracy));
    });

    test('at easy, 8 of 10 reads as 0.63 — under the bar', () {
      final acc = _window(
        correct: 8,
        other: 2,
        at: QuestionDifficulty.easy,
      ).levelWeightedAccuracy!;
      expect(acc, closeTo(8 * 0.6 / (8 * 0.6 + 2 * 1.4), 1e-9));
      expect(acc, lessThan(PolicyConstants.recheckRecentAccuracy));
    });

    test('a partial answer counts against, like a wrong one', () {
      expect(
        _window(
          correct: 7,
          other: 3,
          otherQuality: AnswerQuality.partial,
        ).levelWeightedAccuracy,
        closeTo(0.7, 1e-9),
      );
    });
  });
}
