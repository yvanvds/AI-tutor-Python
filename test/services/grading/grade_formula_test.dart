// The grade formula (#99) against PUNTENFORMULE part 2: the worked example
// of bijlage B must come out to the point, the core gate must respect the
// milestone's expected level, `d` counts only among mastered LOs, growth
// is clamped, and beliefs are read *after* decay.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/grading/grade_formula.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:flutter_test/flutter_test.dart';

LoGradeInput _in(bool mastered, [QuestionDifficulty? highest]) =>
    LoGradeInput(mastered: mastered, highest: highest);

List<MilestoneLo> _los({required int core, required int extension}) => [
  for (var i = 0; i < core; i++)
    MilestoneLo(subgoalId: 's', loId: 'k$i', isCore: true),
  for (var i = 0; i < extension; i++)
    MilestoneLo(subgoalId: 's', loId: 'u$i', isCore: false),
];

void main() {
  group('bijlage B (v1 placeholders: C(k)=k, w_u=0.6, w_d=0.4, w_M=0.6, '
      'w_G=0.4)', () {
    test('student A: 8/8 core, 2/3 extension, 4 of 10 at hard → 72', () {
      final los = _los(core: 8, extension: 3);
      final inputs = <String, LoGradeInput>{};
      // Core: all mastered at medium, four of them at hard.
      for (var i = 0; i < 8; i++) {
        inputs['s/k$i'] = _in(
          true,
          i < 4 ? QuestionDifficulty.hard : QuestionDifficulty.medium,
        );
      }
      inputs['s/u0'] = _in(true, QuestionDifficulty.medium);
      inputs['s/u1'] = _in(true, QuestionDifficulty.medium);
      inputs['s/u2'] = _in(false, QuestionDifficulty.easy);

      final m = computeMasteryScore(
        los: los,
        inputs: inputs,
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(m.k, 1.0);
      expect(m.u, closeTo(0.667, 1e-3));
      expect(m.d, closeTo(0.4, 1e-9));
      expect(m.m, closeTo(78.0, 0.05));

      final g = growthScore(mStart: 40, mEnd: m.m);
      expect(g, closeTo(0.633, 1e-3));
      expect(roundedProposal(proposalScore(mEnd: m.m, g: g)), 72);
    });

    test('student B: 7/8 core, 1/3 extension, nothing at hard → 50', () {
      final los = _los(core: 8, extension: 3);
      final inputs = <String, LoGradeInput>{};
      for (var i = 0; i < 7; i++) {
        inputs['s/k$i'] = _in(true, QuestionDifficulty.medium);
      }
      inputs['s/k7'] = _in(false, QuestionDifficulty.medium);
      inputs['s/u0'] = _in(true, QuestionDifficulty.medium);

      final m = computeMasteryScore(
        los: los,
        inputs: inputs,
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(m.k, 0.875);
      expect(m.u, closeTo(0.333, 1e-3));
      expect(m.d, 0.0);
      expect(m.m, closeTo(52.5, 1e-9));

      final g = growthScore(mStart: 10, mEnd: m.m);
      expect(g, closeTo(0.472, 1e-3));
      expect(roundedProposal(proposalScore(mEnd: m.m, g: g)), 50);
    });
  });

  group('core gate (§2.2)', () {
    test('a mastered core LO demonstrated below the expected level does not '
        'count towards k, but still counts as mastered for d', () {
      final los = _los(core: 2, extension: 0);
      final inputs = {
        's/k0': _in(true, QuestionDifficulty.hard),
        's/k1': _in(true, QuestionDifficulty.easy),
      };
      final m = computeMasteryScore(
        los: los,
        inputs: inputs,
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(m.coreCounted, 1);
      expect(m.k, 0.5);
      expect(m.masteredTotal, 2);
      expect(m.d, 0.5);
    });

    test('an expected level of hard requires the ratchet on hard', () {
      final los = _los(core: 1, extension: 0);
      final m = computeMasteryScore(
        los: los,
        inputs: {'s/k0': _in(true, QuestionDifficulty.medium)},
        expectedDifficulty: QuestionDifficulty.hard,
      );
      expect(m.k, 0.0);
      expect(m.m, 0.0);
    });

    test('half the core caps the top: extension work cannot lift M past '
        '50·k + 50·k·(…)', () {
      final los = _los(core: 2, extension: 2);
      final m = computeMasteryScore(
        los: los,
        inputs: {
          's/k0': _in(true, QuestionDifficulty.hard),
          's/k1': _in(false),
          's/u0': _in(true, QuestionDifficulty.hard),
          's/u1': _in(true, QuestionDifficulty.hard),
        },
        expectedDifficulty: QuestionDifficulty.medium,
      );
      // k = 0.5, u = 1, d = 1 → 25 + 25·(0.6 + 0.4) = 50.
      expect(m.m, closeTo(50.0, 1e-9));
    });
  });

  group('edge cases', () {
    test('no LO in the milestone → M = 0', () {
      final m = computeMasteryScore(
        los: const [],
        inputs: const {},
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(m.m, 0.0);
      expect(m.d, 0.0);
    });

    test('an LO without a belief doc is never probed: not mastered', () {
      final m = computeMasteryScore(
        los: _los(core: 1, extension: 1),
        inputs: const {},
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(m.k, 0.0);
      expect(m.u, 0.0);
    });

    test('full core, full extension, everything at hard → 100', () {
      final m = computeMasteryScore(
        los: _los(core: 3, extension: 2),
        inputs: {
          for (var i = 0; i < 3; i++)
            's/k$i': _in(true, QuestionDifficulty.hard),
          for (var i = 0; i < 2; i++)
            's/u$i': _in(true, QuestionDifficulty.hard),
        },
        expectedDifficulty: QuestionDifficulty.hard,
      );
      expect(m.m, closeTo(100.0, 1e-9));
    });
  });

  group('growth (§2.4)', () {
    test('closes half the gap → 0.5', () {
      expect(growthScore(mStart: 40, mEnd: 70), closeTo(0.5, 1e-9));
    });
    test('regression counts as 0, not negative', () {
      expect(growthScore(mStart: 60, mEnd: 40), 0.0);
    });
    test('started at 100: no gap to close, G = 1', () {
      expect(growthScore(mStart: 100, mEnd: 100), 1.0);
      expect(growthScore(mStart: 100, mEnd: 90), 1.0);
    });
    test('the proposal is a whole point on 100', () {
      expect(roundedProposal(72.1), 72);
      expect(roundedProposal(72.5), 73);
      expect(roundedProposal(100.4), 100);
    });
  });

  group('LoGradeInput.fromBelief reads the belief post-decay', () {
    final now = DateTime.utc(2026, 9, 2);

    LoBelief belief({
      required double alpha,
      required double beta,
      required DateTime at,
      bool calibrated = true,
      QuestionDifficulty? highest = QuestionDifficulty.medium,
    }) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: alpha,
      beta: beta,
      lastUpdatedAt: at,
      lastPositiveAtCalibratedAt: calibrated ? at : null,
      highestPositiveDifficulty: highest,
    );

    test('a fresh (5, 1) is mastered', () {
      final i = LoGradeInput.fromBelief(
        belief(alpha: 5, beta: 1, at: now.subtract(const Duration(days: 1))),
        now: now,
      );
      expect(i.mastered, isTrue);
      expect(i.highest, QuestionDifficulty.medium);
    });

    test('the same belief four months untouched has decayed out of '
        'mastery (evidence below the minimum)', () {
      final i = LoGradeInput.fromBelief(
        belief(alpha: 5, beta: 1, at: now.subtract(const Duration(days: 120))),
        now: now,
      );
      expect(i.mastered, isFalse);
    });

    test('condition 3: no calibrated positive → not mastered however high '
        'the mean', () {
      final i = LoGradeInput.fromBelief(
        belief(
          alpha: 10,
          beta: 1,
          at: now,
          calibrated: false,
          highest: QuestionDifficulty.easy,
        ),
        now: now,
      );
      expect(i.mastered, isFalse);
      expect(i.highest, QuestionDifficulty.easy);
    });

    test('a missing doc is never probed', () {
      final i = LoGradeInput.fromBelief(null, now: now);
      expect(i.mastered, isFalse);
      expect(i.highest, isNull);
    });
  });
}
