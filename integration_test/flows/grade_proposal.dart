// End-to-end (#99): the periodic grade proposal, teacher side.
//
//   1. The teacher defines a milestone on the Milestones page — subgoals,
//      the Angoff split per learning objective, the expected level, the
//      period — and it lands in `milestones`.
//   2. In a student's detail drawer the teacher computes the proposal
//      against a seeded milestone: the number is the formula's, from the
//      seeded beliefs and history (PUNTENFORMULE bijlage B arithmetic;
//      M_start from the history estimate, as no period-start snapshot was
//      taken for this student — period_start_snapshot.dart drives the
//      exact path, #110);
//      asks the model for the justification — the prompt carries that
//      number as a fixed fact and only the period's status reports; adjusts
//      the grade with a note; signs off. The `grade_proposals` doc holds
//      the computed number, the model's text and the teacher's decision.
//   3. A student's shell has no Milestones entry at all.
//
// Real app, real navigation, the real Students page and drawer over the
// in-memory Cosmos; only the model is scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/grade_proposal.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/milestones/milestones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kJustification =
    'Sam beheerst de kern en toonde print() op moeilijk niveau aan.';

final DateTime _now = DateTime.now().toUtc();
final DateTime _periodStart = _now.subtract(const Duration(days: 30));

Map<String, dynamic> _belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  required int daysAgo,
  required String highest,
}) {
  final at = _now.subtract(Duration(days: daysAgo)).toIso8601String();
  return {
    'id': '${kStudentUid}_${subgoalId}_$loId',
    'type': 'lo_belief',
    'uid': kStudentUid,
    'subgoalId': subgoalId,
    'loId': loId,
    'alpha': alpha,
    'beta': beta,
    'lastUpdatedAt': at,
    'lastPositiveAtCalibratedAt': at,
    'highestPositiveDifficulty': highest,
    'recentNegativesAtCalibrated': 0,
    'firstMasteredAt': at,
  };
}

Map<String, dynamic> _milestone() => {
  'id': 'm1',
  'type': 'milestone',
  'title': 'Rapport 1',
  'periodStart': _periodStart.toIso8601String(),
  'dueAt': _now.add(const Duration(days: 7)).toIso8601String(),
  'expectedDifficulty': 'medium',
  'subgoalIds': ['s1', 's2'],
  'coreLoKeys': ['s1/lo-print'],
  'updatedAt': _now.toIso8601String(),
};

Map<String, dynamic> _sample(String goalId, double progress, int daysAgo) {
  final at = _now.subtract(Duration(days: daysAgo));
  return {
    'id': '${at.toIso8601String()}_seed$goalId',
    'uid': kStudentUid,
    'goalId': goalId,
    'progress': progress,
    'at': at.toIso8601String(),
  };
}

Map<String, dynamic> _report(String goalId, String text, int daysAgo) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'statusReport': text,
  'updatedAt': _now.subtract(Duration(days: daysAgo)).toIso8601String(),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The drawer's outer list; the sections below the fold are only built
  /// once scrolled to.
  Finder drawerList() => find
      .descendant(
        of: find.byType(StudentDetailDrawer),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the drawer's *outer* list to the bottom until [finder] is built,
  /// then brings it into view. Not `scrollUntilVisible`: that drags at the
  /// list's centre, which here lands on the nested goal list and scrolls
  /// that one instead.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(drawerList()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  testWidgets('teacher defines a milestone with an Angoff split and it is '
      'stored', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Milestones'));
    await pumpUntilFound(tester, find.byType(MilestonesPage));
    await tester.tap(find.text('New milestone'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('milestone-title')),
      'Rapport 1',
    );
    final due = formatIsoDate(_now.add(const Duration(days: 40)));
    await tester.enterText(find.byKey(const Key('milestone-due-at')), due);
    // The goal tree arrives on the 5 s poll.
    await pumpUntilFound(tester, find.byKey(const Key('milestone-subgoal-s1')));
    await tester.tap(find.byKey(const Key('milestone-subgoal-s1')));
    await tester.pump();
    // The LO row appears with the default answer "extension"; flip it.
    final loToggle = find.byKey(const Key('milestone-lo-s1/lo-print'));
    expect(loToggle, findsOneWidget);
    await tester.tap(
      find.descendant(of: loToggle, matching: find.text('core')),
    );
    await tester.pump();
    expect(
      find.text('1 core, 0 extension learning objectives'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('milestone-save')));
    await pumpUntilFound(tester, find.text('Milestone saved.'));

    final docs = harness.cosmos['milestones'].docs.values.toList();
    expect(docs, hasLength(1));
    final doc = docs.single;
    expect(doc['title'], 'Rapport 1');
    expect(doc['subgoalIds'], ['s1']);
    expect(doc['coreLoKeys'], ['s1/lo-print']);
    expect(doc['expectedDifficulty'], 'medium');
    expect(
      DateTime.parse(doc['dueAt'] as String).toLocal().day,
      _now.add(const Duration(days: 40)).toLocal().day,
    );
    // And the list on the left now shows it.
    await pumpUntilFound(tester, find.byKey(Key('milestone-row-${doc['id']}')));

    await harness.dispose(tester);
  });

  testWidgets('teacher computes, justifies, adjusts and signs off a grade '
      'proposal in the student drawer', (tester) async {
    final llm = ScriptedLlm([kJustification]);
    final harness = AppHarness(
      identity: teacherIdentity,
      llm: llm,
      extraDocs: {
        'accounts': [accountDoc(studentIdentity)],
        'milestones': [_milestone()],
        'lo_beliefs': [
          // Core LO, mastered and demonstrated at hard: k = 1, and the one
          // hard ratchet among the two mastered LOs: d = 0.5.
          _belief(
            's1',
            'lo-print',
            alpha: 6,
            beta: 1,
            daysAgo: 5,
            highest: 'hard',
          ),
          // Extension LO, mastered at medium: u = 1.
          _belief(
            's2',
            'lo-var',
            alpha: 5,
            beta: 1,
            daysAgo: 3,
            highest: 'medium',
          ),
        ],
        // "Print" was already done before the period (k_start = 1, u_start
        // = 0 → M_start = 50); "Variables" was finished inside it.
        'progress_history': [_sample('s1', 1.0, 45), _sample('s2', 1.0, 10)],
        'status_reports': [
          _report('s2', 'Werkt vlot met variabelen.', 2),
          _report('s1', 'OUD RAPPORT van voor de periode.', 60),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    await tester.tap(find.text('Sam Student'));
    await pumpUntilFound(tester, find.byType(StudentDetailDrawer));

    // The section sits at the bottom of the drawer; the milestone list
    // arrives on its poll and the earliest milestone is picked by default.
    await reveal(tester, find.text('Grade proposal'));
    await pumpUntilFound(tester, find.byKey(const Key('grade-compute')));
    await reveal(tester, find.byKey(const Key('grade-compute')));
    await tester.tap(find.byKey(const Key('grade-compute')));
    await pumpUntilFound(tester, find.byKey(const Key('grade-proposal')));

    // M_end = 50 + 50·(0.6·1 + 0.4·0.5) = 90; M_start = 50; G = 0.8;
    // P = 0.6·90 + 0.4·80 = 86.
    expect(
      tester.widget<Text>(find.byKey(const Key('grade-proposal'))).data,
      '86',
    );
    expect(find.text('Mastery now: 90.0'), findsOneWidget);
    expect(find.text('Mastery at period start: 50.0'), findsOneWidget);
    // No period-start snapshot was ever taken for this student: the
    // history estimate is the fallback, and the drawer says so (#110).
    expect(
      tester.widget<Text>(find.byKey(const Key('grade-start-source'))).data,
      'Period start: estimate from progress history '
      '(no snapshot for this period)',
    );
    expect(find.text('Growth: 0.80'), findsOneWidget);
    expect(find.text('Core at level: 1 / 1'), findsOneWidget);
    expect(find.text('Extension mastered: 1 / 1'), findsOneWidget);
    expect(find.text('Demonstrated at hard: 1 / 2 mastered'), findsOneWidget);
    // No model call was needed for the number.
    expect(llm.sends, 0);

    await reveal(tester, find.byKey(const Key('grade-justify')));
    await tester.tap(find.byKey(const Key('grade-justify')));
    await pumpUntilFound(tester, find.byKey(const Key('grade-justification')));
    expect(find.text(kJustification), findsOneWidget);
    expect(llm.sends, 1);
    // The model was told the number, and only the period's reports.
    final prompt = llm.sentInputs.single;
    expect(prompt, contains('"proposal":86'));
    expect(prompt, contains('Werkt vlot met variabelen.'));
    expect(prompt, isNot(contains('OUD RAPPORT')));

    // Adjust for what the system cannot see, then sign.
    await reveal(tester, find.byKey(const Key('grade-sign-off')));
    await tester.enterText(find.byKey(const Key('grade-adjusted')), '84');
    await tester.enterText(
      find.byKey(const Key('grade-note')),
      'Ziek in week 3.',
    );
    await tester.tap(find.byKey(const Key('grade-sign-off')));
    await pumpUntilFound(tester, find.byKey(const Key('grade-signed')));
    expect(
      tester.widget<Text>(find.byKey(const Key('grade-signed'))).data,
      contains('84/100'),
    );
    // The signed proposal is locked: no recompute, no rewrite.
    expect(find.byKey(const Key('grade-compute')), findsNothing);
    expect(find.byKey(const Key('grade-justify')), findsNothing);

    final doc = harness.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['proposal'], 86);
    expect(doc['adjustedGrade'], 84);
    expect(doc['adjustmentNote'], 'Ziek in week 3.');
    expect(doc['justification'], kJustification);
    expect(doc['signedOffAt'], isA<String>());
    expect(doc['mStartSource'], 'history');
    expect(doc['formulaVersion'], '1.0.7');

    await harness.dispose(tester);
  });

  testWidgets('a student has no Milestones entry and no grade anywhere', (
    tester,
  ) async {
    final harness = AppHarness(
      extraDocs: {
        'milestones': [_milestone()],
      },
    );
    await harness.boot(tester);
    expect(find.byTooltip('Milestones'), findsNothing);
    expect(find.byTooltip('Students'), findsNothing);
    await harness.dispose(tester);
  });
}
