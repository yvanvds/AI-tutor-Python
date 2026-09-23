// End-to-end (#169): a wrong answer weighs by the level it was asked at —
// the other way round from a correct one. A student calibrated at `hard`
// who gets the first exercise wrong takes a strong negative of
// 2.0 × 0.6 = 1.2 on β, not the 2.0 × 1.4 = 2.8 a *correct* answer at hard
// adds to α; the same mistake by a student calibrated at `easy` costs
// 2.0 × 1.4 = 2.8. Both land in Cosmos: the `turn_history` doc names the
// difficulty asked and the applied `betaDelta`, the `lo_beliefs` doc
// carries the weighted β. Nothing on screen shows the number; the docs are
// the user-visible surface, and everything the belief steers — question
// choice, stuck detection, the progress bar, mastery — reads them.
//
// Before #169 the factor was symmetric and both students took the mirror
// of a correct answer's weight: 2.8 at hard, 1.2 at easy. That made μ plain
// accuracy at whatever level the calibration ladder had parked the student
// (40–75% by construction), under the 0,80 mastery bar by design.
//
// Real app, real navigation, real explain and practice views and editor,
// real TutorService → conductor → belief math → Cosmos services. Only the
// model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/difficulty_asymmetry.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// One graded turn: the exercise on mount, a wrong grade with a strong
/// negative on the seeded LO, and the exercise the app asks for next so the
/// script is never exhausted mid-flow.
List<String> wrongTurnScript() => [
  completeCodeReply(text: 'Vul de naam in.', code: kExercise),
  codeFeedbackReply(
    text: 'Dat klopt niet: de naam is niet ingevuld.',
    quality: 'wrong',
    loSignals: const [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'strong',
      },
    ],
  ),
  completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
];

/// The seeded account calibrated at [difficulty], so the first exercise is
/// asked at that level and the negative lands at it.
Map<String, dynamic> studentAt(String difficulty) => {
  ...accountDoc(studentIdentity),
  'calibration': {
    'difficulty': difficulty,
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The text actually rendered in the practice editor.
  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Boots, reaches the practice editor with the first exercise loaded,
  /// sends it unchanged (the grade is scripted as wrong) and waits for the
  /// grade to be integrated and the next exercise to arrive.
  Future<void> answerWrongOnce(WidgetTester tester, AppHarness harness) async {
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
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

  Map<String, dynamic> singleTurn(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.single;

  Map<String, dynamic> singleBelief(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs.values.single;

  /// The one applied signal on the turn: the target's own negative.
  Map<dynamic, dynamic> appliedNegative(Map<String, dynamic> turn) {
    final applied = (turn['appliedSignals'] as List).cast<Map>();
    expect(applied, hasLength(1));
    expect(applied.single['loId'], 'lo-print');
    expect(applied.single['subgoalId'], 's1');
    expect((applied.single['alphaDelta'] as num).toDouble(), 0.0);
    return applied.single;
  }

  testWidgets('a wrong answer at hard costs 2.0 × 0.6 on β: less than the '
      'same mistake at medium, and less than a correct answer at hard '
      'earns', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(wrongTurnScript()),
      extraDocs: {
        'accounts': [studentAt('hard')],
      },
    );
    await answerWrongOnce(tester, harness);

    final turn = singleTurn(harness);
    expect(turn['difficulty'], 'hard');
    expect(turn['overallQuality'], 'wrong');
    // strong (2.0) × the negative factor at hard (0.6) × home (1.0).
    final debit = (appliedNegative(turn)['betaDelta'] as num).toDouble();
    expect(debit, closeTo(2.0 * 0.6, 1e-9));
    expect(debit, lessThan(2.0));

    final belief = singleBelief(harness);
    expect(belief['loId'], 'lo-print');
    expect(belief['alpha'], closeTo(PolicyConstants.prior, 1e-9));
    expect(belief['beta'], closeTo(PolicyConstants.prior + 2.0 * 0.6, 1e-9));
    // A negative at the calibrated level: a strike, no ratchet.
    expect(belief['recentNegativesAtCalibrated'], 1);
    expect(belief['highestPositiveDifficulty'], isNull);
    expect(belief['lastPositiveAtCalibratedAt'], isNull);

    await harness.dispose(tester);
  });

  testWidgets('the same wrong answer at easy costs 2.0 × 1.4 on β: more '
      'than at medium', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(wrongTurnScript()),
      extraDocs: {
        'accounts': [studentAt('easy')],
      },
    );
    await answerWrongOnce(tester, harness);

    final turn = singleTurn(harness);
    expect(turn['difficulty'], 'easy');
    // strong (2.0) × the negative factor at easy (1.4) × home (1.0).
    final debit = (appliedNegative(turn)['betaDelta'] as num).toDouble();
    expect(debit, closeTo(2.0 * 1.4, 1e-9));
    expect(debit, greaterThan(2.0));

    final belief = singleBelief(harness);
    expect(belief['alpha'], closeTo(PolicyConstants.prior, 1e-9));
    expect(belief['beta'], closeTo(PolicyConstants.prior + 2.0 * 1.4, 1e-9));

    await harness.dispose(tester);
  });
}
