// End-to-end (#278, formula 1.1): the stuck rule counts own questions. An
// LO is stuck once it got six questions of its own and its mean is still
// under 0.6 (CONDUCTOR_POLICY §4.4) — not when `α + β` reaches 10, which
// forgetting per answer no longer says anything about.
//
// The teacher saw students move on with an LO marked stuck just as they
// began to get it (#245): a doc heavy with old wrong answers read as
// "tried enough" on the evidence alone. Here "Variables" has `lo-var`
// mastered and `lo-cast` low on a heavy doc from before the count, (3, 9):
// stuck by the old rule. A wrong answer on it no longer moves the student
// on — the next exercise is on "Variables" again, the doc counts its first
// own question, and the answer lands after forgetting. With five own
// questions on record the sixth wrong answer does make it stuck: the
// subgoal advances with the stuck LO named, and the app celebrates.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → stuck rule → advance →
// Cosmos. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/stuck_own_questions.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'getal = ___(input("Getal: "))\nprint(getal + 1)';
const String kAgain = 'leeftijd = ___(input("Leeftijd: "))\nprint(leeftijd)';
const String kNextSubgoal = 'for i in range(___):\n    print(i)';

/// The wrong answer on `lo-cast`, the subgoal's one LO not mastered.
String wrongOnCast() => codeFeedbackReply(
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
);

/// "Print" is done.
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'advancedAt': '2026-08-03T10:00:00Z',
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// "Variables" with an LO the student has and one they struggle with, and
/// a "Loops" subgoal for the walk to land on.
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

/// `lo-var`: mastered and stamped, (9, 1).
Map<String, dynamic> varMastered(DateTime at) => {
  'id': '${kStudentUid}_s2_lo-var',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': 'lo-var',
  'alpha': 9.0,
  'beta': 1.0,
  'lastUpdatedAt': at.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': at.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'firstMasteredAt': at.toIso8601String(),
  'recentNegativesAtCalibrated': 0,
};

/// `lo-cast` at (3, 9): μ 0.25 on evidence 12 — stuck by the rule before
/// #278 (`α + β ≥ 10` and μ < 0.6). [ownQuestions] absent: a doc from
/// before the count, which reads 0.
Map<String, dynamic> castLow(DateTime at, {int? ownQuestions}) => {
  'id': '${kStudentUid}_s2_lo-cast',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': 'lo-cast',
  'alpha': 3.0,
  'beta': 9.0,
  'lastUpdatedAt': at.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'recentNegativesAtCalibrated': 0,
  if (ownQuestions != null) 'ownQuestions': ownQuestions,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Finder celebration() => find.descendant(
    of: find.byType(GoalSplashOverlay),
    matching: find.text('Goal reached!'),
  );

  /// Onto "Variables", the first exercise in the editor, and the answer
  /// sent.
  Future<void> answerFirst(WidgetTester tester, AppHarness harness) async {
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == kExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    await tester.tap(find.byTooltip('Send to tutor'));
  }

  Map<String, dynamic> castDoc(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s2_lo-cast']!;

  testWidgets('a heavy, low doc from before the count is not stuck: a wrong '
      'answer keeps the student on the subgoal and counts the first own '
      'question', (tester) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Zet de invoer om.', code: kExercise),
        wrongOnCast(),
        completeCodeReply(text: 'Nog eens.', code: kAgain),
      ]),
      extraDocs: {
        'goals': curriculum(),
        'progress': [printDone()],
        'lo_beliefs': [varMastered(now), castLow(now)],
      },
    );
    await answerFirst(tester, harness);

    // The next exercise is on "Variables" again: no advance, no splash.
    await pumpUntil(
      tester,
      () => editorText(tester) == kAgain,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise on "Variables" never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle after the answer',
    );
    expect(celebration(), findsNothing);
    expect(harness.llm!.remaining, 0);

    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalId'], 's2');
    expect(turn['targetLOIds'], ['lo-cast']);
    expect(turn['subgoalAdvanced'], isFalse);
    final status = (turn['loStatusAfter'] as List).cast<Map>().singleWhere(
      (s) => s['loId'] == 'lo-cast',
    );
    expect(status['stuck'], isFalse);
    expect(status['mean'] as num, lessThan(0.6));
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s2']?['advancedAt'],
      isNull,
    );

    // The doc counts its first own question, and the wrong answer landed
    // after forgetting: (1 + 2 × 0.7, 1 + 8 × 0.7) + (0, 2).
    final cast = castDoc(harness);
    expect(cast['ownQuestions'], 1);
    final kept = forgetBeforeEvidence(const BeliefSnapshot(3, 9));
    expect(cast['alpha'], closeTo(kept.alpha, 1e-3));
    expect(cast['beta'], closeTo(kept.beta + 2.0, 1e-3));

    await harness.dispose(tester);
  });

  testWidgets('the sixth own question still wrong makes it stuck: the '
      'subgoal advances with the stuck LO named, and the walk moves on', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Zet de invoer om.', code: kExercise),
        wrongOnCast(),
        llmEnvelope(
          text: 'Sam kent variabelen; omzetten naar een getal blijft moeilijk.',
          meta:
              '{"type":"status_summary","stats":{"hints_used":0,'
              '"common_issues":[],"last_exercise_type":"complete_code"}}',
        ),
        completeCodeReply(text: 'Nu een lus.', code: kNextSubgoal),
      ]),
      extraDocs: {
        'goals': curriculum(),
        'progress': [printDone()],
        'lo_beliefs': [varMastered(now), castLow(now, ownQuestions: 5)],
      },
    );
    await answerFirst(tester, harness);

    // The grade advances "Variables" and the app celebrates. Tap it away,
    // as a student would; that also keeps its 10 s auto-dismiss from
    // reaching into a container this test has already torn down.
    await pumpUntilFound(tester, celebration());
    await tester.tap(celebration());
    await pumpUntilGone(tester, celebration());
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextSubgoal,
      timeout: const Duration(seconds: 30),
      reason: 'the next subgoal\'s exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle after the advance',
    );

    expect(castDoc(harness)['ownQuestions'], 6);
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalAdvanced'], isTrue);
    final events = (turn['signalEvents'] as List).cast<Map>();
    final stuckAdvance = events.singleWhere(
      (e) => e['kind'] == 'stuckLoAdvance',
    );
    expect((stuckAdvance['details'] as Map)['stuckLoIds'], ['lo-cast']);
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s2']!['advancedAt'],
      isA<String>(),
    );

    await harness.dispose(tester);
  });
}
