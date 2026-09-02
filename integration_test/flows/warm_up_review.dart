// End-to-end (#102): a session opens with one short review question on an
// older, once-mastered LO whose belief has gone stale. The student mastered
// "Print" six weeks ago and is now on "Variables"; the first exercise of the
// session is a warm-up on `lo-print`, announced in chat, and its grade lands
// on the old belief doc like any direct probe — decayed α plus the full
// weight, decay clock reset, ratchets moved — with the turn recorded against
// the old subgoal. The next exercise is the ordinary first probe of
// "Variables". A student whose old LO was written recently gets no warm-up.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → instruction generator → grader payload → conductor → belief
// math → Cosmos services. Only the model is scripted (`ScriptedLlm`, raw
// assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/warm_up_review.dart -d windows

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

const String kWarmUpExercise = 'print(___)';
const String kVariablesExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// The warm-up exercise on the old LO, its grade, and the exercise the app
/// asks for next (the active subgoal's first probe).
List<String> warmUpScript() => [
  completeCodeReply(
    text: 'Even opwarmen: toon een tekst.',
    code: kWarmUpExercise,
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

/// No warm-up due: the first exercise is the active subgoal's.
List<String> plainScript() => [
  completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
];

/// "Print" is done: its progress is cached at 1.0, so the conductor lands
/// the student on "Variables".
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'updatedAt': '2026-07-20T10:00:00Z',
  'lastSessionAt': '2026-07-20T10:00:00Z',
};

/// The belief on `lo-print` as it was last written at [lastUpdatedAt].
Map<String, dynamic> printBelief({required DateTime lastUpdatedAt}) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 5.0,
  'beta': 1.0,
  'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  'lastQuestionType': 'writeCodeQuestion',
  'lastPositiveAtCalibratedAt': lastUpdatedAt.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  'firstMasteredAt': lastUpdatedAt.toIso8601String(),
};

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

  final sixWeeksAgo = DateTime.now().toUtc().subtract(
    PolicyConstants.warmUpStaleAfter + const Duration(days: 12),
  );

  testWidgets('the session opens with a review question on the stale LO; '
      'its grade refreshes the old belief and the next exercise is the '
      "active subgoal's", (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(warmUpScript()),
      extraDocs: {
        'progress': [printDone()],
        'lo_beliefs': [printBelief(lastUpdatedAt: sixWeeksAgo)],
      },
    );
    await openPractice(tester, harness, firstExercise: kWarmUpExercise);

    // The ritual is announced, naming the old topic.
    expect(
      pills(tester),
      contains(contains('one review question on Print')),
      reason: 'no pill announced the warm-up',
    );

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

    // The turn is recorded against the old subgoal, flagged as a warm-up.
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['isWarmUp'], isTrue);
    expect(turn['subgoalId'], 's1');
    expect(turn['targetLOIds'], ['lo-print']);
    expect(turn['difficulty'], 'medium');
    expect(turn['calibrationAfter'], turn['calibrationBefore']);
    final applied = (turn['appliedSignals'] as List).cast<Map>();
    expect(applied.single['loId'], 'lo-print');
    expect(applied.single['alphaDelta'], closeTo(2.0, 1e-9));

    // The old belief was refreshed like any direct probe.
    final print = storedPrint(harness);
    final writtenAt = DateTime.parse(print['lastUpdatedAt'] as String);
    expect(
      DateTime.now().toUtc().difference(writtenAt),
      lessThan(const Duration(minutes: 1)),
    );
    final decayed = applyDecay(
      alpha: 5,
      beta: 1,
      lastUpdatedAt: sixWeeksAgo,
      now: writtenAt,
    );
    expect(decayed.alpha, lessThan(5));
    expect(print['alpha'], closeTo(decayed.alpha + 2.0, 1e-9));
    expect(print['beta'], closeTo(decayed.beta, 1e-9));
    expect(print['highestPositiveDifficulty'], 'medium');
    expect(
      DateTime.parse(print['lastPositiveAtCalibratedAt'] as String),
      writtenAt,
    );
    expect(print['firstMasteredAt'], sixWeeksAgo.toIso8601String());
    expect(print['lastQuestionType'], 'completeCodeQuestion');

    // The active subgoal was not touched by the warm-up, and "Print" keeps
    // its cached progress: a review is not a re-enrolment.
    expect(
      harness.cosmos['lo_beliefs'].docs.containsKey('${kStudentUid}_s2_lo-var'),
      isFalse,
    );
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress'],
      1.0,
    );
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });

  testWidgets('an old LO written recently is not stale: no warm-up, the '
      "first exercise is the active subgoal's", (tester) async {
    final recently = DateTime.now().toUtc().subtract(const Duration(days: 5));
    final harness = AppHarness(
      llm: ScriptedLlm(plainScript()),
      extraDocs: {
        'progress': [printDone()],
        'lo_beliefs': [printBelief(lastUpdatedAt: recently)],
      },
    );
    await openPractice(tester, harness, firstExercise: kVariablesExercise);

    expect(
      pills(tester),
      isNot(contains(contains('review question'))),
      reason: 'a warm-up was announced for a fresh LO',
    );
    expect(storedPrint(harness)['lastUpdatedAt'], recently.toIso8601String());
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });
}
