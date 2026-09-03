// End-to-end (#100): the weight a graded answer adds to a belief depends on
// where the student was when they answered. With a supervision registry that
// says "in an Anchor session", a strong-positive at medium moves α by
// 2.0 × s (PUNTENFORMULE §2.7); with the app's own binding — no registry —
// it moves α by 2.0, exactly as before, and the turn is recorded as home
// work. Both facts land in Cosmos: the `turn_history` doc names the
// provenance and the `lo_beliefs` doc carries the weighted α.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → belief math → Cosmos services. Only the model is
// scripted (`ScriptedLlm`, raw assistant text through the production
// parser) and, in the first test, the registry Anchor will one day back.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/evidence_provenance.dart -d windows

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

/// A registry that has every student in a clean, active session, and
/// remembers who it was asked about.
class _InSession implements SupervisionSource {
  final List<({String uid, DateTime at})> asked = [];

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async {
    asked.add((uid: uid, at: at));
    return EvidenceProvenance.supervised;
  }
}

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// One graded turn: the exercise on mount, the grade for the submitted code
/// (a clean strong positive on the seeded LO), and the exercise the app asks
/// for next so the script is never exhausted mid-flow.
List<String> gradedTurnScript() => [
  completeCodeReply(text: 'Vul de naam in.', code: kExercise),
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
  completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The text actually rendered in the practice editor.
  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Boots, reaches the practice editor with the first exercise loaded, and
  /// sends that code to the tutor — the moment the grade is integrated.
  Future<void> answerOnce(WidgetTester tester, AppHarness harness) async {
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
    // The grade was integrated and the app moved on to the next exercise.
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

  double appliedAlpha(Map<String, dynamic> turn) {
    final applied = (turn['appliedSignals'] as List).cast<Map>();
    expect(applied, hasLength(1));
    expect(applied.single['loId'], 'lo-print');
    return (applied.single['alphaDelta'] as num).toDouble();
  }

  testWidgets('an answer given in a supervised session is recorded as such '
      'and weighted by the supervised factor', (tester) async {
    final registry = _InSession();
    final harness = AppHarness(
      llm: ScriptedLlm(gradedTurnScript()),
      supervision: registry,
    );
    await answerOnce(tester, harness);

    // The registry was asked about this student, not about the class.
    expect(registry.asked.map((q) => q.uid), [kStudentUid]);

    const s = PolicyConstants.supervisedWeightFactor;
    final turn = singleTurn(harness);
    expect(turn['provenance'], 'supervised');
    // strong (2.0) × medium (1.0) × s
    expect(appliedAlpha(turn), closeTo(2.0 * s, 1e-9));

    final belief = singleBelief(harness);
    expect(belief['loId'], 'lo-print');
    expect(belief['alpha'], closeTo(PolicyConstants.prior + 2.0 * s, 1e-9));
    expect(belief['beta'], closeTo(PolicyConstants.prior, 1e-9));

    await harness.dispose(tester);
  });

  testWidgets('without a supervision registry the same answer is home work '
      'at the unit weight', (tester) async {
    final harness = AppHarness(llm: ScriptedLlm(gradedTurnScript()));
    await answerOnce(tester, harness);

    final turn = singleTurn(harness);
    expect(turn['provenance'], 'home');
    expect(appliedAlpha(turn), closeTo(2.0, 1e-9));

    final belief = singleBelief(harness);
    expect(belief['alpha'], closeTo(PolicyConstants.prior + 2.0, 1e-9));

    await harness.dispose(tester);
  });
}
