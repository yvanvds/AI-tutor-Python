// End-to-end (#117): the language picked in Options is the language the
// tutor writes in. Until this issue the picker switched the interface only —
// the model's language was implicit in the teacher-authored instruction
// bodies, which are written in Dutch, so an English-interface student was
// asked questions and given feedback in Dutch.
//
// What the app actually controls is the *prompt*, so that is what this flow
// asserts on: the system prompt of every request the running app sends, as
// the scripted model receives it (`ScriptedLlm.sentInstructions`). Whether a
// given model then obeys is not something a test can settle without calling
// OpenAI, and no test here does.
//
// Real app, real navigation, real Options page, real practice view and
// editor, real TutorService → conductor → prompt assembly. Only the model is
// scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/tutor_language.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
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

  testWidgets('the language chosen in Options is the language the tutor is '
      'told to write to the student in', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Fill in the name.', code: kExercise),
      codeFeedbackReply(text: 'Helemaal juist.', quality: 'correct'),
      completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    // The app boots in English (the harness pins an en-US desktop), so the
    // first exercise is asked for in English.
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

    expect(llm.sentInstructions, hasLength(1));
    expect(
      llm.sentInstructions.first,
      contains('Write all student-facing text in English'),
      reason: 'the first request carried no English output-language directive',
    );
    expect(llm.sentInstructions.first, isNot(contains('Dutch (Nederlands)')));
    // The transport contract is still there, and the machine half of it is
    // explicitly exempted from translation.
    expect(llm.sentInstructions.first, contains('RESPONSE FORMAT — STRICT.'));
    expect(
      llm.sentInstructions.first,
      contains('Never translate the machine parts'),
    );

    // The student switches to Dutch, the way a student does.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));

    await tester.tap(find.byTooltip('Sessie'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    // Switching language does not throw away the exercise in flight — no
    // extra request went out while the student was in Options.
    expect(llm.sentInstructions, hasLength(1));
    expect(editorText(tester), kExercise);

    // Sending the answer grades it and asks for the next exercise: both go
    // out in the newly chosen language.
    await tester.tap(find.byTooltip('Stuur naar tutor'));
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );

    expect(llm.remaining, 0);
    expect(llm.sentInstructions.length, greaterThanOrEqualTo(3));
    for (final instructions in llm.sentInstructions.skip(1)) {
      expect(
        instructions,
        contains('Write all student-facing text in Dutch (Nederlands)'),
        reason: 'a request after the switch still asked for English',
      );
      expect(instructions, isNot(contains('text in English')));
    }

    await harness.dispose(tester);
  });
}
