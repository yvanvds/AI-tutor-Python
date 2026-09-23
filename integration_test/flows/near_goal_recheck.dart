// End-to-end (#187): a near goal the student left behind gets one check
// question in the middle of practice, and a right answer earns the stamp
// the grade reads.
//
// In the first report round ten of fifteen reports needed a teacher
// adjustment for the same profile: an LO just under the bar (μ 0.74–0.80),
// asked on hard, then left behind for two or three weeks while the student
// did well on later subgoals. Nothing in the app would ever ask it again —
// practice only probes the active subgoal, the warm-up review only once-
// mastered LOs after 30 days — and decay pulls a belief toward the prior,
// never over the bar. Now the conductor's recheck slot (CONDUCTOR_POLICY
// §2.6) asks it: here `lo-print` sits at μ 0.77, last asked twelve days
// ago (a signal from the side two days ago moved the belief, not the
// probe clock), and the student's last ten answers were right. The first
// exercise of the session is a check question on "Print", announced in
// chat; the answer lands on the old belief doc as a direct probe, which
// completes the three mastery conditions and sets `firstMasteredAt`; the
// turn is recorded against "Print", flagged as a recheck, with the
// subgoal the student was on; and the next exercise is "Variables" again.
// A student whose recent work is not good is not sent back.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → question request → grader payload → belief
// math → Cosmos services. Only the model is scripted (`ScriptedLlm`, raw
// assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/near_goal_recheck.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kRecheckExercise = 'print(___)';
const String kVariablesExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// The check question on the old LO, its grade, and the exercise the app
/// asks for next (the active subgoal's first probe).
List<String> recheckScript() => [
  completeCodeReply(
    text: 'Tussendoor: toon een tekst op het scherm.',
    code: kRecheckExercise,
  ),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  ),
  completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
];

/// No recheck: the first exercise is the active subgoal's.
List<String> plainScript() => [
  completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
];

/// The student moved past "Print" on a stuck-advance: finished, with
/// `lo-print` not mastered — so the conductor lands on "Variables".
Map<String, dynamic> printAdvancedPast(DateTime at) => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 0.0,
  'updatedAt': at.toIso8601String(),
  'lastSessionAt': at.toIso8601String(),
  'advancedAt': at.toIso8601String(),
};

/// `lo-print` just under the bar — (7.7, 2.3), μ 0.77, never demonstrated —
/// last asked directly at [probedAt], last written at [updatedAt].
Map<String, dynamic> nearBelief({
  required DateTime probedAt,
  required DateTime updatedAt,
}) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 7.7,
  'beta': 2.3,
  'lastUpdatedAt': updatedAt.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'recentNegativesAtCalibrated': 0,
  'lastProbedAt': probedAt.toIso8601String(),
};

/// The seeded account with a full calibration window at medium: [correct]
/// of the ten answers right.
Map<String, dynamic> accountWithWindow({required int correct}) {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return {
    ...accountDoc(studentIdentity),
    'calibration': {
      'difficulty': 'medium',
      'recentAnswers': [
        for (var i = 0; i < PolicyConstants.calibrationWindow; i++)
          {
            'quality': i < correct ? 'correct' : 'wrong',
            'difficulty': 'medium',
            'at': at.toIso8601String(),
          },
      ],
      'recentQuestionTypes': const <String>[],
    },
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  /// Boots onto "Variables" (no lesson content, so the leerpad opens the
  /// practice editor directly) and waits for the first exercise.
  Future<void> openPractice(
    WidgetTester tester,
    AppHarness harness, {
    required String firstExercise,
  }) async {
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == firstExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the first exercise never reached the editor',
    );
  }

  Map<String, dynamic> storedPrint(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print']!;

  final now = DateTime.now().toUtc();
  final twelveDaysAgo = now.subtract(const Duration(days: 12));
  final twoDaysAgo = now.subtract(const Duration(days: 2));

  testWidgets('a near goal left behind gets one check question mid-practice; '
      'the right answer earns the stamp and practice goes on', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(recheckScript()),
      extraDocs: {
        'accounts': [accountWithWindow(correct: 10)],
        'progress': [printAdvancedPast(twelveDaysAgo)],
        'lo_beliefs': [
          nearBelief(probedAt: twelveDaysAgo, updatedAt: twoDaysAgo),
        ],
      },
    );
    await openPractice(tester, harness, firstExercise: kRecheckExercise);

    // The student sees why this question is about an older topic.
    expect(
      pills(tester),
      contains(contains('one check question on Print')),
      reason: 'no pill announced the recheck',
    );
    expect(pills(tester), isNot(contains(contains('review question'))));

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded after the code was sent',
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == kVariablesExercise,
      timeout: const Duration(seconds: 30),
      reason: "the active subgoal's exercise never reached the editor",
    );

    // The grader was told the target lives in "Print".
    final grading =
        jsonDecode(harness.llm!.sentInputs[1]) as Map<String, dynamic>;
    final target = (grading['target_los'] as List).cast<Map>().single;
    expect(target['id'], 'lo-print');
    expect(target['subgoalId'], 's1');

    // The turn is recorded against "Print", as a recheck, naming the
    // subgoal the student was practising.
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['isRecheck'], isTrue);
    expect(turn.containsKey('isWarmUp'), isFalse);
    expect(turn['subgoalId'], 's1');
    expect(turn['activeSubgoalId'], 's2');
    expect(turn['targetLOIds'], ['lo-print']);
    expect(turn['difficulty'], 'medium');
    expect(turn['calibrationAfter'], turn['calibrationBefore']);
    expect(
      (turn['selectionReason'] as Map)['chosenReason'],
      contains('recheck'),
    );
    final applied = (turn['appliedSignals'] as List).cast<Map>();
    expect(applied.single['subgoalId'], 's1');
    expect(applied.single['alphaDelta'], closeTo(2.0, 1e-9));

    // A direct probe of the old LO: decayed α plus the full weight — over
    // the bar now, with the calibrated positive — so the stamp is set.
    final print = storedPrint(harness);
    final writtenAt = DateTime.parse(print['lastUpdatedAt'] as String);
    expect(
      DateTime.now().toUtc().difference(writtenAt),
      lessThan(const Duration(minutes: 1)),
    );
    final decayed = applyDecay(
      alpha: 7.7,
      beta: 2.3,
      lastUpdatedAt: twoDaysAgo,
      now: writtenAt,
    );
    expect(print['alpha'], closeTo(decayed.alpha + 2.0, 1e-9));
    expect(print['beta'], closeTo(decayed.beta, 1e-9));
    final mean =
        (print['alpha'] as num) /
        ((print['alpha'] as num) + (print['beta'] as num));
    expect(mean, greaterThanOrEqualTo(PolicyConstants.masteryMeanThreshold));
    expect(print['lastPositiveAtCalibratedAt'], print['lastUpdatedAt']);
    expect(print['highestPositiveDifficulty'], 'medium');
    expect(print['firstMasteredAt'], print['lastUpdatedAt']);
    expect(print['lastProbedAt'], print['lastUpdatedAt']);

    // Not a calibrated probe of "Variables": the window is as it was, and
    // no subgoal cache moved.
    final account = harness.cosmos['accounts'].docs[kStudentUid]!;
    final window = (account['calibration'] as Map)['recentAnswers'] as List;
    expect(window, hasLength(PolicyConstants.calibrationWindow));
    expect(window.every((a) => (a as Map)['quality'] == 'correct'), isTrue);
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress'],
      0.0,
    );
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });

  testWidgets('a student whose recent work is not good is not sent back: '
      "the first exercise is the active subgoal's", (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(plainScript()),
      extraDocs: {
        'accounts': [accountWithWindow(correct: 5)],
        'progress': [printAdvancedPast(twelveDaysAgo)],
        'lo_beliefs': [
          nearBelief(probedAt: twelveDaysAgo, updatedAt: twelveDaysAgo),
        ],
      },
    );
    await openPractice(tester, harness, firstExercise: kVariablesExercise);

    expect(
      pills(tester),
      isNot(contains(contains('check question'))),
      reason: 'a recheck was announced for a struggling student',
    );
    expect(
      storedPrint(harness)['lastProbedAt'],
      twelveDaysAgo.toIso8601String(),
    );
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });
}
