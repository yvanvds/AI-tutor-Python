// End-to-end (#225): a student who starts with "Continue" ("Verder") in the
// learning path and finishes the last subgoal of a goal goes on to the next
// goal — and the first answer there counts for the LO it asked about.
//
// "Continue" prefers the goal (`preferredRoot`) without a subgoal. The
// conductor used to clear that preference on an advance only when a
// subgoal was preferred too, so after the last subgoal of the goal the walk
// put the student on the next goal's first subgoal while the old goal
// stayed active. The grader got the old goal's LOs as its scope, the scope
// check dropped every signal on the new subgoal — the one on the asked LO
// included — and a side signal on the old goal kept the fallback away: the
// LO stayed at the prior, the next question asked it again, and the bar
// stayed at 0, oefening after oefening, until the app restarted. The
// learning path showed it too: the old goal as the one in progress.
//
// A signal on the asked LO that still falls outside the scope is the app's
// error, not the grader's: the turn carries a `targetSignalLost` event, an
// audit line in the teacher's drawer for that student.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → advance → Cosmos → leerpad.
// Only the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/next_root_signal.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kNewGoalExercise = 'print(3 ___ 5)';
const String kNextExercise = 'print(7 ___ 7)';

/// The turns in the order the app asks for them: the exercise on
/// "Variables", the grade that masters `lo-var` (the last subgoal of
/// "Basics", so the walk goes on to "Conditions"), the status report on the
/// finished subgoal, the first exercise on "Comparisons", its grade — on
/// the asked `lo-cmp`, and a side remark on `lo-var` of the old goal — and
/// the exercise after it.
List<String> script() => [
  completeCodeReply(text: 'Vul de stad in.', code: kExercise),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's2',
        'loId': 'lo-var',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  ),
  llmEnvelope(
    text: 'Sam kent variabelen.',
    meta:
        '{"type":"status_summary","stats":{"hints_used":0,'
        '"common_issues":[],"last_exercise_type":"complete_code"}}',
  ),
  completeCodeReply(text: 'Vergelijk twee getallen.', code: kNewGoalExercise),
  codeFeedbackReply(
    text: 'Juist vergeleken.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's3',
        'loId': 'lo-cmp',
        'signal': 'positive',
        'strength': 'strong',
      },
      {
        'subgoalId': 's2',
        'loId': 'lo-var',
        'signal': 'positive',
        'strength': 'weak',
      },
    ],
  ),
  completeCodeReply(text: 'Nog een vergelijking.', code: kNextExercise),
];

/// "Print" is done, so "Variables" is the last open subgoal of "Basics".
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'advancedAt': '2026-08-03T10:00:00Z',
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// A second goal after "Basics", with one subgoal.
List<Map<String, dynamic>> nextGoal() => [
  goalDoc(id: 'r2', title: 'Conditions', order: 2000),
  goalDoc(
    id: 's3',
    title: 'Comparisons',
    parentId: 'r2',
    order: 1000,
    objectives: [objective('lo-cmp', 'Compare two values')],
  ),
];

/// One strong positive short of mastery, calibrated positive on record:
/// (3, 1) reads 0.75 on evidence 4; the grade adds 2.0 to α at medium and
/// (5, 1) reads 0.83 on 6 — mastered, and "Variables" advances.
Map<String, dynamic> varBelief(DateTime at) => {
  'id': '${kStudentUid}_s2_lo-var',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': 'lo-var',
  'alpha': 3.0,
  'beta': 1.0,
  'lastUpdatedAt': at.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': at.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
};

/// A turn in "Comparisons" whose strong positive on the asked `lo-cmp` was
/// dropped by a grading scope still on "Basics", while a side remark on
/// `lo-var` survived — what the conductor records since #225. The event is
/// the app's own, serialised as the conductor writes it.
Map<String, dynamic> lostTurn() => {
  'id': 'lost-1',
  'type': 'turn_history',
  'uid': kStudentUid,
  'turnAt': DateTime.now().toUtc().toIso8601String(),
  'subgoalId': 's3',
  'targetLOIds': ['lo-cmp'],
  'questionType': 'completeCodeQuestion',
  'difficulty': 'medium',
  'isFollowUp': false,
  'chainDepth': 0,
  'overallQuality': 'correct',
  'loSignals': [
    {
      'subgoalId': 's2',
      'loId': 'lo-var',
      'signal': 'positive',
      'strength': 'weak',
    },
  ],
  'hadFallback': false,
  'appliedSignals': const [],
  'provenance': 'home',
  'calibrationBefore': 'medium',
  'calibrationAfter': 'medium',
  'subgoalProgressAfter': 0.0,
  'loStatusAfter': const [],
  'subgoalAdvanced': false,
  'signalEvents': [
    TurnSignalEvent.of(
      TurnSignalEventKind.targetSignalLost,
      details: {
        'subgoalId': 's3',
        'loId': 'lo-cmp',
        'signal': 'positive',
        'strength': 'strong',
        'activeRootId': 'r1',
        'fallback': false,
      },
    ).toJson(),
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Finder card(String rootId) =>
      find.byWidgetPredicate((w) => w is LeerpadCard && w.root.id == rootId);

  Finder continueIn(String rootId) =>
      find.descendant(of: card(rootId), matching: find.text('Continue'));

  testWidgets('after "Continue" and the last subgoal of a goal, the first '
      'answer in the next goal is graded in that goal\'s scope and counts '
      'for the LO it asked about; the learning path shows the next goal in '
      'progress', (tester) async {
    final llm = ScriptedLlm(script());
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': nextGoal(),
        'progress': [printDone()],
        'lo_beliefs': [varBelief(DateTime.now().toUtc())],
      },
    );
    await harness.boot(tester);

    // "Continue" on "Basics": onto "Variables" (no lesson content, so the
    // practice editor opens).
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(continueIn('r1'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == kExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    await tester.tap(find.byTooltip('Send to tutor'));

    // The grade finishes "Variables", and with it "Basics". Tap the
    // celebration away, as a student would; that also keeps its 10 s
    // auto-dismiss from reaching into a container this test has already
    // torn down.
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);

    // The walk went on to "Comparisons", the first subgoal of
    // "Conditions".
    await pumpUntil(
      tester,
      () => editorText(tester) == kNewGoalExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next goal\'s exercise never reached the editor',
    );
    expect(
      find.descendant(
        of: find.byType(ObjectiveBanner),
        matching: find.text('Comparisons'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == 2,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded for the answer in the next goal',
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise after it never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle',
    );
    expect(llm.remaining, 0);

    // The grader was told the new goal's LOs, and only those.
    final gradings = [
      for (final input in llm.sentInputs)
        jsonDecode(input) as Map<String, dynamic>,
    ].where((r) => r['request_type'] == 'submit_code').toList();
    expect(gradings, hasLength(2));
    final grading = gradings.last;
    expect(
      (grading['target_los'] as List).cast<Map>().map(
        (lo) => '${lo['subgoalId']}/${lo['id']}',
      ),
      ['s3/lo-cmp'],
    );
    expect(
      (grading['goal_scope_los'] as List).cast<Map>().map(
        (lo) => '${lo['subgoalId']}/${lo['id']}',
      ),
      ['s3/lo-cmp'],
    );

    // The signal on the asked LO arrived and was applied; the remark on
    // the old goal is out of scope now. Nothing was lost.
    final turn = harness.cosmos['turn_history'].docs.values.singleWhere(
      (t) => t['subgoalId'] == 's3',
    );
    expect(turn['targetLOIds'], ['lo-cmp']);
    expect(turn['loSignals'], [
      {
        'subgoalId': 's3',
        'loId': 'lo-cmp',
        'signal': 'positive',
        'strength': 'strong',
      },
    ]);
    expect(turn['hadFallback'], isFalse);
    expect(
      (turn['appliedSignals'] as List).cast<Map>().single['loId'],
      'lo-cmp',
    );
    expect(turn.containsKey('signalEvents'), isFalse);
    final cmp = harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s3_lo-cmp'];
    expect(cmp, isNotNull);
    expect(cmp!['alpha'], closeTo(3.0, 1e-9));
    expect(cmp['highestPositiveDifficulty'], 'medium');

    // The learning path shows "Conditions" as the goal in progress, with
    // its "Continue"; "Basics" is done.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, card('r2'));
    expect(continueIn('r2'), findsOneWidget);
    expect(continueIn('r1'), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('a grade lost on the asked LO is an audit line in the '
      'teacher\'s drawer, without a badge', (tester) async {
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'accounts': [accountDoc(studentIdentity)],
        'goals': nextGoal(),
        'turn_history': [lostTurn()],
      },
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    // The badge stream has answered by the time the row is there; give it a
    // poll's worth of frames anyway before saying it stays away.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('Unacknowledged signal events'), findsNothing);

    await tester.tap(find.text('Sam Student'));
    await pumpUntilEndDrawerOpen(tester, find.byType(StudentDetailDrawer));
    await pumpUntilFound(
      tester,
      find.text('Grade on the asked LO lost (audit)'),
    );
    expect(find.textContaining('subgoalId: s3 · loId: lo-cmp'), findsOneWidget);
    // Nothing to acknowledge: an audit line is not a badge.
    expect(find.text('Acknowledge (0)'), findsOneWidget);

    await harness.dispose(tester);
  });
}
