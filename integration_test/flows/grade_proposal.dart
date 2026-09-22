// End-to-end (#99, #148, #149): the periodic grade proposal, teacher side,
// now as a class-wide workflow.
//
//   1. The teacher defines a milestone on the Milestones page — subgoals,
//      the Angoff split per learning objective, the expected level, the
//      period — and it lands in `milestones`. A milestone whose report date
//      has gone by with nothing generated for it is flagged in that list
//      (#148), and the flag clears once the reports exist.
//   2. On the Reports page the teacher picks the milestone (the selector
//      shows its title — an untitled milestone used to make it render
//      blank), narrows to one class and presses "Generate reports". The
//      batch computes the deterministic number for every student in one
//      pass (PUNTENFORMULE bijlage B arithmetic; M_start from the history
//      estimate, as no period-start snapshot was taken for this student —
//      period_start_snapshot.dart drives the exact path, #110) and asks the
//      model for one justification per student who needs one. A student
//      with no belief data on the milestone lands on "no data" instead of a
//      computed 0, and costs no model call. The teacher then walks the
//      class in the detail pane, adjusts a grade with a note and signs off.
//   3. The justification is the teacher's to rewrite (#149), before signing
//      and after: a recompute that moves the number drops AI prose but
//      keeps theirs, flagged stale, and PUNTENFORMULE §5 freezes the grade,
//      not the sentence explaining it.
//   4. The student detail drawer no longer carries any of this: sign-off
//      lives in exactly one place.
//   5. A student's shell has no Milestones and no Reports entry at all.
//
// Real app, real navigation, the real Students page, Milestones page and
// Reports page over the in-memory Cosmos; only the model is scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/grade_proposal.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/milestones/milestones_page.dart';
import 'package:ai_tutor_python/features/reports/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kJustification =
    'Sam beheerst de kern en toonde print() op moeilijk niveau aan.';

/// A classmate of Sam's who never worked on the milestone's objectives.
const String kQuietUid = 'it-quiet';

final DateTime _now = DateTime.now().toUtc();
final DateTime _periodStart = _now.subtract(const Duration(days: 30));

Map<String, dynamic> _belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  required int daysAgo,
  required String highest,
  String uid = kStudentUid,
}) {
  final at = _now.subtract(Duration(days: daysAgo)).toIso8601String();
  return {
    'id': '${uid}_${subgoalId}_$loId',
    'type': 'lo_belief',
    'uid': uid,
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

Map<String, dynamic> _milestone({
  String id = 'm1',
  String title = 'Rapport 1',
  int dueInDays = 7,
}) => {
  'id': id,
  'type': 'milestone',
  'title': title,
  'periodStart': _periodStart.toIso8601String(),
  'dueAt': _now.add(Duration(days: dueInDays)).toIso8601String(),
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

/// The seeded student, plus a classmate in the same class who has no belief
/// data at all. Both carry the class the Reports page filters on.
List<Map<String, dynamic>> _classDocs() => [
  {...accountDoc(studentIdentity), 'className': '5A'},
  {
    'id': kQuietUid,
    'uid': kQuietUid,
    'email': 'kim@example.com',
    'firstName': 'Kim',
    'lastName': 'Zwijger',
    'targetGoal': 'Python',
    'mayUseGlobalKey': true,
    'className': '5A',
    'calibration': {
      'difficulty': 'medium',
      'recentAnswers': <String>[],
      'recentQuestionTypes': <String>[],
    },
  },
];

Map<String, List<Map<String, dynamic>>> _gradedClass() => {
  'accounts': _classDocs(),
  'milestones': [_milestone()],
  'lo_beliefs': [
    // Core LO, mastered and demonstrated at hard: k = 1, and the one hard
    // ratchet among the two mastered LOs: d = 0.5.
    _belief('s1', 'lo-print', alpha: 6, beta: 1, daysAgo: 5, highest: 'hard'),
    // Extension LO, mastered at medium: u = 1.
    _belief('s2', 'lo-var', alpha: 5, beta: 1, daysAgo: 3, highest: 'medium'),
  ],
  // "Print" was already done before the period (k_start = 1, u_start = 0 →
  // M_start = 50); "Variables" was finished inside it.
  'progress_history': [_sample('s1', 1.0, 45), _sample('s2', 1.0, 10)],
  'status_reports': [
    _report('s2', 'Werkt vlot met variabelen.', 2),
    _report('s1', 'OUD RAPPORT van voor de periode.', 60),
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Opens the Reports page and waits for the class list to be there.
  Future<void> openReports(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Reports'));
    await pumpUntilFound(tester, find.byType(ReportsPage));
    await pumpUntilFound(tester, find.byKey(const Key('reports-milestone')));
  }

  /// Scrolls [key] into the detail pane's view and taps it. The pane is a
  /// `ListView`, so an action below the fold is not hit-testable yet.
  Future<void> tapInDetail(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  String chipText(WidgetTester tester, String uid) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(Key('reports-status-$uid')),
          matching: find.byType(Text),
        ),
      )
      .data!;

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
    // And the list on the left now shows it — with no overdue flag: the
    // report date is still ahead.
    await pumpUntilFound(tester, find.byKey(Key('milestone-row-${doc['id']}')));
    expect(find.byKey(Key('milestone-overdue-${doc['id']}')), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('an untitled milestone cannot be saved from the bottom of the '
      'editor', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Milestones'));
    await pumpUntilFound(tester, find.byType(MilestonesPage));
    await tester.tap(find.text('New milestone'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('milestone-due-at')),
      formatIsoDate(_now.add(const Duration(days: 40))),
    );
    await pumpUntilFound(tester, find.byKey(const Key('milestone-subgoal-s1')));
    await tester.tap(find.byKey(const Key('milestone-subgoal-s1')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('milestone-save')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('milestone-save')));
    await pumpUntilFound(tester, find.byKey(const Key('milestone-save-error')));

    expect(
      tester.widget<Text>(find.byKey(const Key('milestone-save-error'))).data,
      'Give the milestone a title.',
    );
    expect(harness.cosmos['milestones'].docs, isEmpty);

    await harness.dispose(tester);
  });

  testWidgets('teacher generates the class\'s reports, walks the list and '
      'signs one off', (tester) async {
    final llm = ScriptedLlm([kJustification]);
    final harness = AppHarness(
      identity: teacherIdentity,
      llm: llm,
      extraDocs: _gradedClass(),
    );
    await harness.boot(tester);

    await openReports(tester);

    // The selector shows the milestone by name. (An untitled milestone used
    // to leave this blank — #148.)
    expect(
      find.descendant(
        of: find.byKey(const Key('reports-milestone')),
        matching: find.text('Rapport 1'),
      ),
      findsOneWidget,
    );

    // Both classmates are listed, on "no data" until the run.
    await pumpUntilFound(tester, find.byKey(Key('reports-row-$kStudentUid')));
    await pumpUntilFound(tester, find.byKey(Key('reports-row-$kQuietUid')));
    expect(chipText(tester, kStudentUid), 'no data');

    // Narrow to the class, then run the batch.
    await tester.tap(find.byKey(const Key('reports-class-filter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('5A').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('reports-generate')));
    await pumpUntil(
      tester,
      () => chipText(tester, kStudentUid) == 'justification',
      reason: 'the batch never justified Sam',
    );

    // The classmate with no belief data is skipped, not handed a 0 — and
    // cost no model call.
    expect(chipText(tester, kQuietUid), 'no data');
    expect(
      tester.widget<Text>(find.byKey(Key('reports-grade-$kQuietUid'))).data,
      '—',
    );
    expect(llm.sends, 1);
    expect(harness.cosmos['grade_proposals'].docs.keys, ['${kStudentUid}_m1']);

    // M_end = 50 + 50·(0.6·1 + 0.4·0.5) = 90; M_start = 50; G = 0.8;
    // P = 0.6·90 + 0.4·80 = 86.
    expect(
      tester.widget<Text>(find.byKey(Key('reports-grade-$kStudentUid'))).data,
      '86',
    );

    // The detail pane carries the whole report.
    await tester.tap(find.byKey(Key('reports-row-$kStudentUid')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('reports-detail-proposal')),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reports-detail-proposal')))
          .data,
      '86',
    );
    expect(find.text('Mastery now: 90.0'), findsOneWidget);
    expect(find.text('Mastery at period start: 50.0'), findsOneWidget);
    // No period-start snapshot was ever taken for this student: the history
    // estimate is the fallback, and the page says so (#110).
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reports-detail-start-source')))
          .data,
      'Period start: estimate from progress history '
      '(no snapshot for this period)',
    );
    expect(find.text('Growth: 0.80'), findsOneWidget);
    expect(find.text('Core at level: 1 / 1'), findsOneWidget);
    expect(find.text('Extension mastered: 1 / 1'), findsOneWidget);
    expect(find.text('Demonstrated at hard: 1 / 2 mastered'), findsOneWidget);
    expect(find.text(kJustification), findsOneWidget);
    // The model was told the number, and only the period's reports.
    final prompt = llm.sentInputs.single;
    expect(prompt, contains('"proposal":86'));
    expect(prompt, contains('Werkt vlot met variabelen.'));
    expect(prompt, isNot(contains('OUD RAPPORT')));

    // Next/prev walk the class without going back to the list.
    await tester.tap(find.byKey(const Key('reports-next')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('reports-detail-name'))).data,
      'Kim Zwijger',
    );
    await tester.tap(find.byKey(const Key('reports-previous')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('reports-detail-name'))).data,
      'Sam Student',
    );

    // Adjust for what the system cannot see, then sign.
    await tester.enterText(find.byKey(const Key('reports-adjusted')), '84');
    await tester.enterText(
      find.byKey(const Key('reports-note')),
      'Ziek in week 3.',
    );
    await tester.tap(find.byKey(const Key('reports-sign-off')));
    await pumpUntilFound(tester, find.byKey(const Key('reports-signed')));
    expect(
      tester.widget<Text>(find.byKey(const Key('reports-signed'))).data,
      contains('84/100'),
    );
    expect(chipText(tester, kStudentUid), 'signed off');
    // The signed proposal is locked: no recompute, no rewrite.
    expect(find.byKey(const Key('reports-run-one')), findsNothing);
    expect(find.byKey(const Key('reports-sign-off')), findsNothing);

    final doc = harness.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['proposal'], 86);
    expect(doc['adjustedGrade'], 84);
    expect(doc['adjustmentNote'], 'Ziek in week 3.');
    expect(doc['justification'], kJustification);
    expect(doc['signedOffAt'], isA<String>());
    expect(doc['mStartSource'], 'history');
    expect(doc['formulaVersion'], '1.0.7');

    // And the drawer that used to own all of this has let it go.
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    await tester.tap(find.text('Sam Student'));
    await pumpUntilFound(tester, find.byType(StudentDetailDrawer));
    expect(find.byKey(const Key('grade-milestone')), findsNothing);
    expect(find.byKey(const Key('grade-compute')), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('teacher rewrites the justification; a recompute keeps the text '
      'and flags it stale, and a signed report can still be rewritten', (
    tester,
  ) async {
    final llm = ScriptedLlm([kJustification]);
    final harness = AppHarness(
      identity: teacherIdentity,
      llm: llm,
      extraDocs: _gradedClass(),
    );
    await harness.boot(tester);

    await openReports(tester);
    await pumpUntilFound(tester, find.byKey(Key('reports-row-$kStudentUid')));
    await tester.tap(find.byKey(Key('reports-row-$kStudentUid')));
    await tester.pump();

    // One student from the detail pane: compute + one model call.
    await tester.tap(find.byKey(const Key('reports-run-one')));
    await pumpUntilFound(tester, find.text(kJustification));
    expect(llm.sends, 1);

    // The model wrote a first draft; the prose is the teacher's (#149).
    const own = 'Sam legde de lus zelf uit tijdens de les.';
    await tapInDetail(tester, const Key('reports-justification-edit'));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('reports-justification-field')),
          )
          .controller!
          .text,
      kJustification,
    );
    await tester.enterText(
      find.byKey(const Key('reports-justification-field')),
      own,
    );
    await tapInDetail(tester, const Key('reports-justification-save'));
    await pumpUntilFound(tester, find.text(own));
    expect(find.text(kJustification), findsNothing);
    expect(
      find.byKey(const Key('reports-justification-edited')),
      findsOneWidget,
    );

    var doc = harness.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['justification'], own);
    expect(doc['justificationSource'], 'edited');
    expect(doc['justificationEditedAt'], isA<String>());
    // Prose only (PUNTENFORMULE §3.3): the number did not move.
    expect(doc['proposal'], 86);

    // Now the evidence moves under the text: the extension LO is no longer
    // mastered, so M_end = 70, G = 0.4 and P = 58. AI prose would be
    // dropped here; the teacher's survives, flagged for rereading — and
    // costs no second model call.
    harness.cosmos['lo_beliefs'].upsert(
      _belief('s2', 'lo-var', alpha: 1, beta: 6, daysAgo: 3, highest: 'medium'),
    );
    await tester.tap(find.byKey(const Key('reports-run-one')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('reports-justification-stale')),
    );
    expect(find.text(own), findsOneWidget);
    expect(llm.sends, 1);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('reports-detail-proposal')))
          .data,
      '58',
    );
    doc = harness.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['proposal'], 58);
    expect(doc['justification'], own);
    expect(doc['justificationStale'], true);

    // Sign off, then rewrite after a conversation with the student: §5
    // freezes the grade, not the sentence explaining it.
    await tester.enterText(find.byKey(const Key('reports-adjusted')), '60');
    await tapInDetail(tester, const Key('reports-sign-off'));
    await pumpUntilFound(tester, find.byKey(const Key('reports-signed')));

    const afterTalk = 'Na ons gesprek: Sam had de opdracht wel begrepen.';
    await tapInDetail(tester, const Key('reports-justification-edit'));
    await tester.enterText(
      find.byKey(const Key('reports-justification-field')),
      afterTalk,
    );
    await tapInDetail(tester, const Key('reports-justification-save'));
    await pumpUntilFound(tester, find.text(afterTalk));

    doc = harness.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['justification'], afterTalk);
    expect(doc['signedOffAt'], isA<String>());
    expect(doc['adjustedGrade'], 60);
    expect(doc['proposal'], 58);
    // The signed report is still locked against a recompute.
    expect(find.byKey(const Key('reports-run-one')), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('a milestone whose report date has passed with no reports is '
      'flagged on the Milestones page', (tester) async {
    final llm = ScriptedLlm([kJustification]);
    final harness = AppHarness(
      identity: teacherIdentity,
      llm: llm,
      extraDocs: {
        ..._gradedClass(),
        'milestones': [_milestone(dueInDays: -2)],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Milestones'));
    await pumpUntilFound(tester, find.byType(MilestonesPage));
    await pumpUntilFound(tester, find.byKey(const Key('milestone-overdue-m1')));

    // Generating the reports answers the nudge, and it clears on the poll.
    await openReports(tester);
    await pumpUntilFound(tester, find.byKey(Key('reports-row-$kStudentUid')));
    await tester.tap(find.byKey(const Key('reports-generate')));
    await pumpUntil(
      tester,
      () => chipText(tester, kStudentUid) == 'justification',
      reason: 'the batch never justified Sam',
    );

    await tester.tap(find.byTooltip('Milestones'));
    await pumpUntilFound(tester, find.byType(MilestonesPage));
    await pumpUntilGone(tester, find.byKey(const Key('milestone-overdue-m1')));

    await harness.dispose(tester);
  });

  testWidgets('a student has no Milestones or Reports entry and no grade '
      'anywhere', (tester) async {
    final harness = AppHarness(
      extraDocs: {
        'milestones': [_milestone()],
      },
    );
    await harness.boot(tester);
    expect(find.byTooltip('Milestones'), findsNothing);
    expect(find.byTooltip('Reports'), findsNothing);
    expect(find.byTooltip('Students'), findsNothing);
    await harness.dispose(tester);
  });
}
