// End-to-end (#103): a graded positive records, on the student's belief doc,
// the highest difficulty it was earned at. A fresh student is calibrated at
// medium, so the first exercise is asked at medium and a correct answer
// lands `highestPositiveDifficulty: "medium"` in the `lo_beliefs` doc —
// the value the grade formula (PUNTENFORMULE §2.2/§2.5) reads at report
// time. Nothing on screen shows it; the doc is the user-visible surface.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → belief math → Cosmos services. Only the model
// is scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/difficulty_ratchet.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  testWidgets('a correct answer at the calibrated difficulty records that '
      'difficulty on the belief doc', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
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
      ]),
    );
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

    // The seeded account is calibrated at medium, so the probe was asked at
    // medium — the turn record says so — and the belief doc ratcheted to it.
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['difficulty'], 'medium');
    final belief = harness.cosmos['lo_beliefs'].docs.values.single;
    expect(belief['loId'], 'lo-print');
    expect(belief['highestPositiveDifficulty'], 'medium');
    expect(belief['lastPositiveAtCalibratedAt'], isA<String>());

    await harness.dispose(tester);
  });
}
