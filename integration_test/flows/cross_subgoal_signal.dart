// End-to-end (#108): a mistake in later work that points to a gap in an
// earlier subgoal reaches that earlier LO's belief. The student mastered
// "Print" three weeks ago and is now on "Variables"; the grader marks the
// answer wrong with a negative on the target *and* a negative on
// `s1/lo-print` (the contract's cross-subgoal `loSignals`), and the app
// debits the old belief doc — decayed β plus the signal's weight as medium,
// its clock reset, nothing else on it moved — and names both signals with
// their subgoal on the `turn_history` doc. An LO never probed before gets a
// fresh doc at the prior plus the signal.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → belief math → Cosmos
// services. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/cross_subgoal_signal.dart -d windows

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

/// The exercise for the active subgoal, a wrong grade that blames the
/// target and the earlier `print()` LO, and the exercise the app asks for
/// next.
List<String> script() => [
  completeCodeReply(text: 'Vul de stad in.', code: kExercise),
  codeFeedbackReply(
    text: 'De variabele klopt niet, en print() mist zijn haakjes.',
    quality: 'wrong',
    loSignals: const [
      {
        'subgoalId': 's2',
        'loId': 'lo-var',
        'signal': 'negative',
        'strength': 'strong',
      },
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'moderate',
      },
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
Map<String, dynamic> printBelief({required DateTime lastUpdatedAt}) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 5.0,
  'beta': 1.0,
  'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': lastUpdatedAt.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  'firstMasteredAt': lastUpdatedAt.toIso8601String(),
};

/// The seeded account, calibrated at `hard` so the probe is asked at hard
/// and the medium treatment of the cross-subgoal signal is observable.
Map<String, dynamic> hardStudent() => {
  ...accountDoc(studentIdentity),
  'calibration': {
    'difficulty': 'hard',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
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

  Map<String, dynamic>? storedPrint(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print'];

  // Three weeks: old enough to have decayed visibly, recent enough that the
  // LO is not yet due for a warm-up review (#102, `warmUpStaleAfter`) —
  // this flow is about an ordinary turn on "Variables", not the review.
  final weeksAgo = DateTime.now().toUtc().subtract(
    PolicyConstants.warmUpStaleAfter - const Duration(days: 9),
  );

  testWidgets('a wrong answer on a later subgoal that blames an earlier LO '
      'debits that LO: decayed β plus the weight as medium, clock reset, '
      'both signals on the turn record', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'accounts': [hardStudent()],
        'progress': [printDone()],
        'lo_beliefs': [printBelief(lastUpdatedAt: weeksAgo)],
      },
    );
    await answerOnce(tester, harness);

    final t = turn(harness);
    expect(t['subgoalId'], 's2');
    expect(t['difficulty'], 'hard');
    final applied = (t['appliedSignals'] as List).cast<Map>();
    expect(applied, hasLength(2));
    final onTarget = applied.singleWhere((a) => a['loId'] == 'lo-var');
    expect(onTarget['subgoalId'], 's2');
    // Strong negative at hard on the target.
    expect(onTarget['betaDelta'], closeTo(2.0 * 1.4, 1e-9));
    final onPrint = applied.singleWhere((a) => a['loId'] == 'lo-print');
    expect(onPrint['subgoalId'], 's1');
    // Moderate negative as medium on the earlier LO — not × 1.4.
    expect(onPrint['betaDelta'], closeTo(PolicyConstants.weightModerate, 1e-9));
    expect(onPrint['alphaDelta'], 0.0);

    final print = storedPrint(harness)!;
    final writtenAt = DateTime.parse(print['lastUpdatedAt'] as String);
    // The clock was reset to the moment of the write, just now.
    expect(
      DateTime.now().toUtc().difference(writtenAt),
      lessThan(const Duration(minutes: 1)),
    );
    // Three weeks of decay on (5, 1), then the signal on β only.
    final decayed = applyDecay(
      alpha: 5,
      beta: 1,
      lastUpdatedAt: weeksAgo,
      now: writtenAt,
    );
    expect(decayed.alpha, lessThan(5));
    expect(print['alpha'], closeTo(decayed.alpha, 1e-9));
    expect(
      print['beta'],
      closeTo(decayed.beta + PolicyConstants.weightModerate, 1e-9),
    );
    // Nothing else on the old doc moved: the hard probe was of `lo-var`.
    expect(print['highestPositiveDifficulty'], 'medium');
    expect(print['lastPositiveAtCalibratedAt'], weeksAgo.toIso8601String());
    expect(print['firstMasteredAt'], weeksAgo.toIso8601String());
    expect(print['recentNegativesAtCalibrated'], 0);
    expect(print['lastQuestionType'], 'completeCodeQuestion');
    // "Print" stays done: the belief is where the regression shows.
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress'],
      1.0,
    );

    await harness.dispose(tester);
  });

  testWidgets('an earlier LO the student was never probed on gets a belief '
      'doc at the prior plus the signal, with nothing certified', (
    tester,
  ) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'progress': [printDone()],
      },
    );
    await answerOnce(tester, harness);

    final print = storedPrint(harness);
    expect(print, isNotNull, reason: 'no belief doc was created for lo-print');
    expect(print!['alpha'], PolicyConstants.prior);
    expect(
      print['beta'],
      closeTo(PolicyConstants.prior + PolicyConstants.weightModerate, 1e-9),
    );
    expect(print.containsKey('lastPositiveAtCalibratedAt'), isFalse);
    expect(print.containsKey('highestPositiveDifficulty'), isFalse);
    expect(print.containsKey('firstMasteredAt'), isFalse);
    expect(print.containsKey('lastQuestionType'), isFalse);

    await harness.dispose(tester);
  });
}
