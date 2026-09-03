// End-to-end (#101): a working solution to a later exercise refreshes the
// earlier LOs it correctly uses. The student mastered "Print" three weeks
// ago and is now on "Variables"; the grader nominates `lo-print` in
// `transferLOs`, and the app lands a small positive on the old belief doc —
// its decayed α plus the weak weight, its decay clock reset — and names the
// credit on the `turn_history` doc. A never-mastered LO gets nothing.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → belief math → Cosmos
// services. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/transfer_credit.dart -d windows

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

const String kExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kNextExercise = 'leeftijd = ___\nprint(leeftijd)';

/// The exercise for the active subgoal, the grade that nominates the
/// earlier LO, and the exercise the app asks for next.
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
    transferLOs: const [
      {'subgoalId': 's1', 'loId': 'lo-print'},
    ],
  ),
  completeCodeReply(text: 'Nu de leeftijd.', code: kNextExercise),
];

/// "Print" is done: its progress is cached at 1.0, so the conductor lands
/// the student on "Variables".
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// The belief on `lo-print` as it was written three weeks ago.
Map<String, dynamic> printBelief({
  required double alpha,
  required double beta,
  required DateTime lastUpdatedAt,
  bool calibratedPositive = true,
  DateTime? firstMasteredAt,
}) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  if (calibratedPositive)
    'lastPositiveAtCalibratedAt': lastUpdatedAt.toIso8601String(),
  if (calibratedPositive) 'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  if (firstMasteredAt != null)
    'firstMasteredAt': firstMasteredAt.toIso8601String(),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Boots onto "Variables" (no lesson content, so the leerpad opens the
  /// practice editor directly), sends the first exercise to the tutor and
  /// waits for the grade to be integrated.
  Future<void> answerOnce(WidgetTester tester, AppHarness harness) async {
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
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded after the code was sent',
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
  }

  Map<String, dynamic> turn(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.single;

  Map<String, dynamic> storedPrint(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print']!;

  // Three weeks: old enough to have decayed visibly, recent enough that the
  // LO is not yet due for a warm-up review (#102, `warmUpStaleAfter`) —
  // this flow is about an ordinary turn on "Variables", not the review.
  final weeksAgo = DateTime.now().toUtc().subtract(
    PolicyConstants.warmUpStaleAfter - const Duration(days: 9),
  );

  testWidgets('a correct answer on a later subgoal refreshes the mastered '
      'LO it used: decayed α plus the weak weight, clock reset, credit '
      'on the turn record', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'progress': [printDone()],
        'lo_beliefs': [
          printBelief(
            alpha: 5,
            beta: 1,
            lastUpdatedAt: weeksAgo,
            firstMasteredAt: weeksAgo,
          ),
        ],
      },
    );
    await answerOnce(tester, harness);

    final t = turn(harness);
    expect(t['subgoalId'], 's2');
    final credits = (t['transferCredits'] as List).cast<Map>();
    expect(credits, hasLength(1));
    expect(credits.single['subgoalId'], 's1');
    expect(credits.single['loId'], 'lo-print');
    expect(
      credits.single['alphaDelta'],
      closeTo(PolicyConstants.weightWeak, 1e-9),
    );

    final print = storedPrint(harness);
    final writtenAt = DateTime.parse(print['lastUpdatedAt'] as String);
    // The clock was reset to the moment of the write, just now.
    expect(
      DateTime.now().toUtc().difference(writtenAt),
      lessThan(const Duration(minutes: 1)),
    );
    // Three weeks of decay on (5, 1), then the credit.
    final decayed = applyDecay(
      alpha: 5,
      beta: 1,
      lastUpdatedAt: weeksAgo,
      now: writtenAt,
    );
    expect(decayed.alpha, lessThan(5));
    expect(
      print['alpha'],
      closeTo(decayed.alpha + PolicyConstants.weightWeak, 1e-9),
    );
    expect(print['beta'], closeTo(decayed.beta, 1e-9));
    // Nothing else on the old doc moved.
    expect(print['highestPositiveDifficulty'], 'medium');
    expect(print['lastPositiveAtCalibratedAt'], weeksAgo.toIso8601String());
    expect(print['firstMasteredAt'], weeksAgo.toIso8601String());
    // A credit is good news: it never flags the LO for review (#112).
    expect(print.containsKey('regressedAt'), isFalse);

    // The target LO got its own ordinary signal.
    final variables =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s2_lo-var']!;
    expect(variables['alpha'], closeTo(PolicyConstants.prior + 2.0, 1e-9));

    await harness.dispose(tester);
  });

  testWidgets('a belief doc written before the mastery stamp existed is '
      'refreshed when it was mastered at its last write, and gets the stamp', (
    tester,
  ) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'progress': [printDone()],
        'lo_beliefs': [printBelief(alpha: 5, beta: 1, lastUpdatedAt: weeksAgo)],
      },
    );
    await answerOnce(tester, harness);

    expect(turn(harness)['transferCredits'], hasLength(1));
    final print = storedPrint(harness);
    expect(print['alpha'], greaterThan(4.0));
    expect(print['firstMasteredAt'], weeksAgo.toIso8601String());

    await harness.dispose(tester);
  });

  testWidgets('an LO that was never mastered is not refreshed, however '
      'confidently the grader nominates it', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'progress': [printDone()],
        'lo_beliefs': [
          // One easy positive, never at calibration: (1.6, 1).
          printBelief(
            alpha: 1.6,
            beta: 1,
            lastUpdatedAt: weeksAgo,
            calibratedPositive: false,
          ),
        ],
      },
    );
    await answerOnce(tester, harness);

    expect(turn(harness).containsKey('transferCredits'), isFalse);
    final print = storedPrint(harness);
    expect(print['alpha'], 1.6);
    expect(print['lastUpdatedAt'], weeksAgo.toIso8601String());
    expect(print.containsKey('firstMasteredAt'), isFalse);

    await harness.dispose(tester);
  });
}
