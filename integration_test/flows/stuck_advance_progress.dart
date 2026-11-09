// End-to-end (#161): the progress of a subgoal the conductor advanced past
// with a stuck LO stays at the honest mastered fraction, and the leerpad
// shows it that way — finished (check mark) with one of its two LOs
// demonstrated and its bar at half, not full. Since #243 the leerpad
// counts the mastery stamps the grade reads: the grade stamps `lo-var`,
// not `lo-cast`.
//
// The teacher saw a student at 100% on every subgoal of a goal while the
// grade proposal named five core LOs as not mastered. Both were right by
// their own definition: the conductor advances a subgoal once every
// non-optional LO is mastered *or stuck* (CONDUCTOR_POLICY §4.4), and on
// that turn it used to force the cached fraction to 1.0 — the number the
// leerpad bars, the XP, the teacher's progress column and the §2.4
// transition rule for M_start all read. Now the fraction stays what it is
// and "finished" travels as the `advancedAt` stamp on the progress doc,
// which is what the next-subgoal walk skips on.
//
// Two oefeningen get it there: the planner asks the stuck `lo-cast` first
// (the lowest mean), answered wrong; then, past the recency guard,
// `lo-var` itself, whose right answer is its second right own question —
// what the stamp wants since formula 1.1 (#279, CONDUCTOR_POLICY §4.1). A
// signal on `lo-var` from the side of a question on `lo-cast`, as this flow
// had it until #282, no longer masters it.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → mastery → advance → progress
// service → Cosmos → leerpad. Only the model is scripted (`ScriptedLlm`,
// raw assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/stuck_advance_progress.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kCastExercise = 'getal = ___(input("Getal: "))\nprint(getal + 1)';
const String kExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kNextExercise = 'for i in range(___):\n    print(i)';

/// The turns in the order the app asks for them: the exercise on the stuck
/// `lo-cast` and its wrong grade, the exercise on `lo-var` and the grade
/// that masters it (which advances the subgoal past the stuck `lo-cast`),
/// the status report the app requests on a finished subgoal, and the next
/// subgoal's first exercise.
List<String> script() => [
  completeCodeReply(text: 'Zet de invoer om.', code: kCastExercise),
  codeFeedbackReply(
    text: 'Nog niet: input() geeft tekst.',
    quality: 'wrong',
    loSignals: const [
      {
        'subgoalId': 's2',
        'loId': 'lo-cast',
        'signal': 'negative',
        'strength': 'strong',
      },
    ],
  ),
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
    text: 'Sam kent variabelen; omzetten naar een getal blijft moeilijk.',
    meta:
        '{"type":"status_summary","stats":{"hints_used":0,'
        '"common_issues":[],"last_exercise_type":"complete_code"}}',
  ),
  completeCodeReply(text: 'Nu een lus.', code: kNextExercise),
];

/// "Print" is done — a doc from before the stamp existed, so the walk also
/// proves a pre-#161 full bar still reads as finished.
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// "Variables" with a second LO the student is stuck on, and a "Loops"
/// subgoal for the walk to land on afterwards.
List<Map<String, dynamic>> curriculum() => [
  goalDoc(
    id: 's2',
    title: 'Variables',
    parentId: 'r1',
    order: 2000,
    objectives: [
      objective('lo-var', 'Assign a value to a name'),
      objective('lo-cast', 'Convert text input to a number'),
    ],
  ),
  goalDoc(
    id: 's3',
    title: 'Loops',
    parentId: 'r1',
    order: 3000,
    objectives: [objective('lo-loop', 'Repeat with a for loop')],
  ),
];

Map<String, dynamic> belief({
  required String loId,
  required double alpha,
  required double beta,
  required DateTime at,
  bool calibratedPositive = false,
  int? ownQuestions,
  int? ownQuestionsRight,
  int? ownQuestionsRightNonMcq,
}) => {
  'id': '${kStudentUid}_s2_$loId',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': at.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  if (calibratedPositive) 'lastPositiveAtCalibratedAt': at.toIso8601String(),
  if (calibratedPositive) 'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  if (ownQuestions != null) 'ownQuestions': ownQuestions,
  if (ownQuestionsRight != null) 'ownQuestionsRight': ownQuestionsRight,
  if (ownQuestionsRightNonMcq != null)
    'ownQuestionsRightNonMcq': ownQuestionsRightNonMcq,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Finder chip(String goalId) => find.byWidgetPredicate(
    (w) => w is LeerpadChildChip && w.goal.id == goalId,
  );

  Finder inChip(String goalId, Finder what) =>
      find.descendant(of: chip(goalId), matching: what);

  testWidgets('advancing past a stuck LO leaves the subgoal at 50% with the '
      'finished mark, on the doc, the history and the leerpad, and the walk '
      'moves on', (tester) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'goals': curriculum(),
        'progress': [printDone()],
        'lo_beliefs': [
          // One strong positive short of mastery, calibrated positive on
          // record: (4.4, 1) reads 0.81 on evidence 5.4; the grade forgets
          // (#278) and adds 2.0 to α at medium, and (5.38, 1) reads 0.84
          // on 6.38. With one right own question on record, no pick, that
          // answer is the second, which the stamp wants (#279): mastered.
          belief(
            loId: 'lo-var',
            alpha: 4.4,
            beta: 1,
            at: now,
            calibratedPositive: true,
            ownQuestions: 1,
            ownQuestionsRight: 1,
            ownQuestionsRightNonMcq: 1,
          ),
          // Low after six own questions: (6, 12) reads 0.33 — stuck (§4.4,
          // #278). The planner asks it first, the lowest mean (since #278
          // no LO is passed over as saturated); answered wrong, it stays
          // stuck, and the recency guard puts the next question on
          // `lo-var`.
          belief(loId: 'lo-cast', alpha: 6, beta: 12, at: now, ownQuestions: 6),
        ],
      },
    );
    await harness.boot(tester);

    // Onto "Variables" (no lesson content, so the practice editor opens).
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    // First the stuck `lo-cast`, answered wrong: no advance yet.
    await pumpUntil(
      tester,
      () => editorText(tester) == kCastExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise on lo-cast never reached the editor',
    );
    await tester.tap(find.byTooltip('Send to tutor'));

    // Then `lo-var` itself.
    await pumpUntil(
      tester,
      () => editorText(tester) == kExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise on lo-var never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle before the answer on lo-var',
    );
    await tester.tap(find.byTooltip('Send to tutor'));

    // The grade advances "Variables" and the app celebrates. Tap it away,
    // as a student would; that also keeps its 10 s auto-dismiss from
    // reaching into a container this test has already torn down.
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);

    // The walk went on to "Loops" — a partial bar on a finished subgoal
    // does not hold the student back …
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next subgoal\'s exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle after the advance',
    );

    // … and the cache is honest: one of two LOs mastered, stamped finished.
    final variables = harness.cosmos['progress'].docs['${kStudentUid}_s2']!;
    expect(variables['progress'], closeTo(0.5, 1e-9));
    expect(variables['advancedAt'], isA<String>());
    // The root rollup is the plain average: (1 + 0.5 + 0) / 3.
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_r1']!['progress'],
      closeTo(0.5, 1e-9),
    );
    // The turn records say the same: the wrong answer on `lo-cast` moved
    // nothing on, and the right one on `lo-var` advanced the subgoal and
    // names the LO the student is stuck on.
    final turns = harness.cosmos['turn_history'].docs.values.toList()
      ..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );
    expect(turns.map((t) => t['targetLOIds']), [
      ['lo-cast'],
      ['lo-var'],
    ]);
    expect(turns.first['subgoalAdvanced'], isFalse);
    final turn = turns.last;
    expect(turn['subgoalId'], 's2');
    expect(turn['subgoalAdvanced'], isTrue);
    expect(turn['subgoalProgressAfter'], closeTo(0.5, 1e-9));
    final events = (turn['signalEvents'] as List).cast<Map>();
    final stuckAdvance = events.singleWhere(
      (e) => e['kind'] == 'stuckLoAdvance',
    );
    expect((stuckAdvance['details'] as Map)['stuckLoIds'], ['lo-cast']);
    // The history sample the §2.4 transition rule reads carries 0.5, not
    // 1.0: after the wrong answer the share was 0, after the advance 0.5.
    final samples =
        harness.cosmos['progress_history'].docs.values
            .where((d) => d['goalId'] == 's2')
            .toList()
          ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
    expect(samples.map((d) => d['progress']).toList(), [0.0, 0.5]);

    // The leerpad shows it that way: "Variables" finished, one of its two
    // LOs demonstrated — the one the grade stamped, on its second right own
    // question — and its bar at half.
    final variable =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s2_lo-var']!;
    expect(variable['firstMasteredAt'], isA<String>());
    expect(variable['ownQuestionsRight'], 2);
    expect(variable['ownQuestionsRightNonMcq'], 2);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntil(
      tester,
      () =>
          inChip('s2', find.text('1 of 2 demonstrated')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the "Variables" chip never read "1 of 2 demonstrated"',
    );
    expect(inChip('s2', find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(
            inChip('s2', find.byType(FractionallySizedBox)),
          )
          .widthFactor,
      closeTo(0.5, 1e-9),
    );
    // "Print" still reads finished from its pre-stamp doc; "Loops" is open;
    // the goal as a whole is not completed.
    expect(inChip('s1', find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(inChip('s3', find.byIcon(Icons.check_circle)), findsNothing);
    expect(find.text('completed'), findsNothing);

    await harness.dispose(tester);
  });
}
