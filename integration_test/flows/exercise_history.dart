// End-to-end (#184): what the model is told across a run of exercises.
//
// Every call used to be able to carry up to 50 messages of conversation;
// now each carries what it needs. A question request goes out with no
// history and names the questions asked before it in a `recent_questions`
// block — one line each, under the LO they were asked for — so the model
// can avoid repeating itself. A grade goes out with its own exercise: the
// question the student answered, and nothing of the exercises before.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → question formatter → connector history bookkeeping. Only
// the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser, history kept by the connector's own code).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/exercise_history.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

const String kFirst = 'print(___)';
const String kSecond = 'naam = ___\nprint(naam)';
const String kThird = 'som = 1 + ___';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Waits until [exercise] is in the editor and the turn that put it there
  /// has finished: the editor fills before the tutor goes idle, and a send
  /// while it is still working is dropped.
  Future<void> waitForExercise(
    WidgetTester tester,
    AppHarness harness,
    String exercise,
  ) => pumpUntil(
    tester,
    () =>
        editorText(tester) == exercise &&
        harness.container.read(tutorServiceProvider) == TutorState.idle,
    timeout: const Duration(seconds: 30),
    reason: 'exercise "$exercise" never reached the editor',
  );

  testWidgets('a question request names the questions asked before; a grade '
      'reads only its own exercise', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Toon een groet.', code: kFirst),
      codeFeedbackReply(
        text: 'Bijna: vergeet de tekst niet.',
        quality: 'partial',
      ),
      completeCodeReply(text: 'Toon je naam.', code: kSecond),
      codeFeedbackReply(text: 'Bijna: welke naam?', quality: 'partial'),
      completeCodeReply(text: 'Maak de som af.', code: kThird),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, harness, kFirst);

    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, harness, kSecond);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, harness, kThird);
    expect(llm.remaining, 0);

    // Question, grade, question, grade, question.
    expect(llm.sentScopes, const [
      PreviousInputs.newSession,
      PreviousInputs.exercise,
      PreviousInputs.newSession,
      PreviousInputs.exercise,
      PreviousInputs.newSession,
    ]);

    Map<String, dynamic> sent(int i) =>
        jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;

    // Question requests carry no history; from the second one on they name
    // what was asked before, oldest first, under the LO it was asked for.
    for (final i in const [0, 2, 4]) {
      expect(llm.sentHistories[i], isEmpty, reason: 'question request $i');
    }
    expect(sent(0).containsKey('recent_questions'), isFalse);
    const firstLine = 'complete_code | lo-print | Toon een groet. `print(___)`';
    const secondLine =
        'complete_code | lo-print | Toon je naam. `naam = ___; print(naam)`';
    expect(sent(2)['recent_questions'], [firstLine]);
    expect(sent(4)['recent_questions'], [firstLine, secondLine]);

    // Each grade reads the question its answer belongs to, and nothing of
    // the exercise before it.
    final firstGrade = llm.sentHistories[1];
    expect(firstGrade, hasLength(1));
    expect(firstGrade.single['role'], 'assistant');
    expect(firstGrade.single['content'], contains('Toon een groet.'));

    final secondGrade = llm.sentHistories[3];
    expect(secondGrade, hasLength(1));
    expect(secondGrade.single['role'], 'assistant');
    expect(secondGrade.single['content'], contains('Toon je naam.'));
    expect(secondGrade.single['content'], isNot(contains('Toon een groet.')));
    expect(sent(3)['request_type'], 'submit_code');

    await harness.dispose(tester);
  });
}
