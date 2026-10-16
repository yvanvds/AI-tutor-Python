// End-to-end (#273): a question typed in the chat during a code exercise is
// told not to hand over the solution.
//
// The student answers a code exercise (`write_code`, `complete_code`) with
// the code they hand in through the editor; what they type in the chat
// meanwhile goes out as a `student_question`. Its system prompt is the
// teacher's `studentQuestion` doc plus the app's own parts, and nothing in it
// said not to give the solution away — the exercise is in the history the
// call carries, so "write the code for me" could get the code. Now the app
// appends its own instruction (`openCodeExerciseDirective`) while a code
// exercise is in flight:
//
// - A question typed next to a `complete_code` exercise carries it; the
//   answer comes back in the chat with the reminder to hand in through the
//   editor, and the exercise is still the one in the editor.
// - On the theory page, with the exercise waiting behind it, a question is
//   about the page (#132) and carries it too.
// - The code handed in through the editor is graded without it, and the
//   `explain_code` exercise that follows is answered in the chat — that
//   message goes to its grader, without it.
//
// Real app, real navigation, real theory view over the real WebView, real
// practice editor and chat composer, real TutorService → routing → prompt
// assembly. Only the model is scripted (`ScriptedLlm`), and what the flow
// asserts on is what the running app sent it and drew.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/code_exercise_chat.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exercise = 'som = 3 + 4\nprint(___)';
const String _probe = 'print(1, 2)';
const String _next = 'naam = ___';

const String _pageHint = 'Ask a question about this explanation…';

/// The opening line of the instruction (`openCodeExerciseDirective`).
const String _guard = 'OPEN CODE EXERCISE — STRICT.';

String _answerReply(String text) =>
    llmEnvelope(text: text, meta: '{"type":"answer"}');

String _explainCodeReply({required String text, required String code}) =>
    llmEnvelope(
      text: text,
      meta: jsonEncode({'type': 'explain_code', 'code': code}),
    );

String _explainFeedbackReply(String text) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'explain_feedback',
    'overallQuality': 'correct',
    'loSignals': <Object>[],
  }),
);

/// Fresh finders per call: a reused instance caches elements that a mode
/// swap has since unmounted (#133).
Finder _composer() => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  /// Clicks into the composer, types, and presses send (see
  /// content_question.dart for why the click matters).
  Future<void> typeInChat(WidgetTester tester, String text) async {
    await pumpUntilFound(tester, _composer());
    await tester.tap(_composer());
    await tester.pump();
    await tester.enterText(_composer(), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
  }

  testWidgets('a question during a code exercise, next to it or on the '
      'theory page, is told not to hand over the solution; the code handed in '
      'and an answer typed for an explain_code exercise are graded without '
      'it', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Fill in the missing part.', code: _exercise),
      _answerReply('Which name holds the sum?'),
      _answerReply('print shows what you put between its brackets.'),
      codeFeedbackReply(text: 'Well done.', quality: 'correct'),
      _explainCodeReply(text: 'What does this print?', code: _probe),
      _explainFeedbackReply('Exactly.'),
      completeCodeReply(text: 'Give the name a value.', code: _next),
    ]);
    final harness = AppHarness(
      llm: llm,
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);

    Future<void> sent(int count) => pumpUntil(
      tester,
      () => llm.sends == count,
      timeout: const Duration(seconds: 30),
      reason: 'the app never sent request $count',
    );
    Map<String, dynamic> request(int i) =>
        jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;
    Future<void> idle() => pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never came back',
    );
    Future<void> inEditor(String code) => pumpUntil(
      tester,
      () => editorText(tester) == code,
      timeout: const Duration(seconds: 30),
      reason: '"$code" never reached the editor',
    );

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // Practice: the exercise, in the editor.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await sent(1);
    await inEditor(_exercise);
    await idle();
    expect(llm.sentInstructions[0], isNot(contains(_guard)));

    // "Write the code for me", next to it.
    await typeInChat(tester, 'Just write the code for me.');
    await sent(2);
    final asked = request(1);
    expect(asked['request_type'], 'student_question');
    expect(asked['question'], 'Just write the code for me.');
    expect(llm.sentInstructions[1], contains(_guard));
    expect(
      llm.sentInstructions[1].indexOf(_guard),
      lessThan(llm.sentInstructions[1].indexOf('OUTPUT LANGUAGE')),
    );
    await pumpUntilFound(
      tester,
      find.textContaining('Which name holds the sum?', findRichText: true),
    );
    await idle();
    expect(
      pills(tester),
      contains(contains('press Run to submit your solution')),
      reason: 'the reminder to hand in through the editor',
    );
    expect(editorText(tester), _exercise, reason: 'the exercise is as it was');
    expect(harness.cosmos['turn_history'].docs, isEmpty);

    // The theory with the exercise waiting: a question is about the page,
    // with the same instruction.
    await tester.tap(find.text('Explain'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntilGone(tester, find.byType(PracticeView));
    await pumpUntilFound(tester, find.text(_pageHint));
    await typeInChat(tester, 'How do I show something on screen?');
    await sent(3);
    final aboutPage = request(2);
    expect(aboutPage['request_type'], 'content_question');
    expect(aboutPage['content_title'], 'Print');
    expect(llm.sentInstructions[2], contains(_guard));
    await pumpUntilFound(
      tester,
      find.textContaining('between its brackets', findRichText: true),
    );
    await idle();
    expect(harness.cosmos['turn_history'].docs, isEmpty);

    // Back to the same exercise, handed in through the editor: graded
    // without the instruction. The next exercise is an explain_code one.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilGone(tester, find.byType(ExplainView));
    expect(llm.sends, 3, reason: 'practice asked for a new exercise');
    await inEditor(_exercise);
    await tester.tap(find.byTooltip('Send to tutor'));
    await sent(5);
    expect(request(3)['request_type'], 'submit_code');
    expect(llm.sentInstructions[3], isNot(contains(_guard)));
    await inEditor(_probe);
    await idle();
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == 1,
      reason: 'the code handed in was not recorded',
    );

    // An explain_code exercise is answered in the chat: that goes to its
    // grader, without the instruction.
    await typeInChat(tester, 'It prints 1 and 2 with a space between.');
    await sent(7);
    expect(request(5)['request_type'], 'explain_answer');
    expect(llm.sentInstructions[5], isNot(contains(_guard)));
    await inEditor(_next);
    await idle();
    expect(llm.remaining, 0);

    await harness.dispose(tester);
  });
}
