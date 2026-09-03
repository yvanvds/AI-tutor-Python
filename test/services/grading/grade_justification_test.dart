// The justification prompt (#99, PUNTENFORMULE §2.6/§3.3): the number goes
// in as a fixed fact, the contract forbids the model an own verdict, the
// evidence is exactly what was passed, and the reply is stored as prose
// even when the model wraps it in the tutor envelope.

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/grading/grade_justification.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:flutter_test/flutter_test.dart';

GradeProposal _proposal() => GradeProposal(
  uid: 'u',
  milestoneId: 'm',
  formulaVersion: '1.0.5',
  computedAt: DateTime.utc(2026, 10, 15),
  k: 1,
  u: 0.5,
  d: 0.25,
  mEnd: 80,
  mStart: 20,
  g: 0.75,
  proposal: 78,
  coreTotal: 4,
  coreCounted: 4,
  extensionTotal: 2,
  extensionMastered: 1,
  masteredTotal: 5,
  hardCount: 1,
  staleLoCount: 1,
  neverProbedCount: 0,
  supervisedTurns: 3,
  homeTurns: 9,
);

Milestone _milestone() => Milestone(
  id: 'm',
  title: 'Rapport 1',
  periodStart: DateTime.utc(2026, 9, 1),
  dueAt: DateTime.utc(2026, 10, 15),
  expectedDifficulty: QuestionDifficulty.medium,
  subgoalIds: const ['s1'],
  coreLoKeys: const {'s1/lo'},
);

void main() {
  test('the prompt carries the computed number as a fixed fact and forbids '
      'the model to pick one', () {
    final p = buildJustificationPrompt(
      proposal: _proposal(),
      milestone: _milestone(),
      studentName: 'Sam',
      calibrationLevel: 'hard',
      reports: const [],
      trajectory: const [],
      languageCode: 'nl',
    );
    expect(p.instructions, contains('78/100'));
    expect(p.instructions, contains('THE NUMBER IS FIXED'));
    expect(p.instructions, contains('Dutch'));
    final input = jsonDecode(p.input) as Map<String, dynamic>;
    expect((input['formula'] as Map)['proposal'], 78);
    expect((input['formula'] as Map)['coreMasteredAtLevel'], '4/4');
    expect((input['reliability'] as Map)['supervisedTurnsInPeriod'], 3);
    // Calibration is context, and labelled as such.
    expect((input['contextOnly'] as Map)['currentDifficultyLevel'], 'hard');
    expect(input['student'], 'Sam');
  });

  test('reports and trajectory are passed through verbatim', () {
    final p = buildJustificationPrompt(
      proposal: _proposal(),
      milestone: _milestone(),
      studentName: 'Sam',
      calibrationLevel: 'medium',
      reports: [
        (
          title: 'Variables',
          text: 'Werkt vlot met variabelen.',
          at: DateTime.utc(2026, 9, 20),
        ),
      ],
      trajectory: const [(title: 'Variables', start: 0.25, end: 1.0)],
      languageCode: 'en',
    );
    expect(p.instructions, contains('English'));
    final input = jsonDecode(p.input) as Map<String, dynamic>;
    final reports = input['statusReportsInPeriod'] as List;
    expect(reports, hasLength(1));
    expect((reports.single as Map)['report'], 'Werkt vlot met variabelen.');
    final traj = input['progressTrajectory'] as List;
    expect((traj.single as Map)['atPeriodStart'], 0.25);
    expect((traj.single as Map)['now'], 1.0);
  });

  group('extractJustificationText', () {
    test('plain prose is trimmed', () {
      expect(extractJustificationText('  Sam did well.\n'), 'Sam did well.');
    });
    test('an envelope reply yields its TEXT body only', () {
      expect(
        extractJustificationText(
          '<TEXT>\nSam did well.\n</TEXT><META>{"type":"status_summary"}</META>',
        ),
        'Sam did well.',
      );
    });
  });
}
