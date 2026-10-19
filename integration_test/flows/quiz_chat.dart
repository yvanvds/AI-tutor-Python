// End-to-end (#271): on a student laptop the chat is there while a quiz is
// open, and what the student types in it is a question, never the quiz's
// answer.
//
// Students in class could not ask the tutor about the theory. Two things hid
// the chat: on a window under 1200 px the theory view starts with it folded
// to a strip whose `<` they did not read as "the chat" (#138), and a pending
// multiple-choice question hid it outright in every mode (#122) — not even
// the strip was left in the theory view. Now the strip shows the tutor's
// avatar, and a quiz hides nothing:
//
// - In practice the quiz sits next to the full chat. A question typed there
//   goes out as a `student_question` carrying the quiz as on screen (its
//   options under the letters the student sees) and the instruction not to
//   give the answer away; nothing is graded, and the quiz still waits for
//   its pick.
// - In the theory view the strip is there with the quiz pending, and a
//   question is about the page on screen (#132), with the same instruction.
// - Back in practice the pick is graded as always, with its key.
//
// The window is a 1366 px laptop at 125 % scaling, 1093 px wide, where the
// quiz gets what the chat leaves of the session; at the end it is made
// 700 px wide, where the chat takes half (#259). Nothing of the quiz may
// run past its column on the way.
//
// Real app, real navigation, real theory view over the real WebView, real
// quiz, real chat composer, real TutorService → routing → prompt assembly.
// Only the model is scripted (`ScriptedLlm`), and what the flow asserts on
// is what the running app sent it and drew.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/quiz_chat.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/tutor_avatar.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

/// A 1366 × 768 laptop at 125 % scaling: the student laptop of #271.
const Size _laptop = Size(1093, 614);

/// The narrow window of #258 and #259.
const double _narrow = 700;

const String _prompt = 'What does this code print?';
const String _code = 'print(1 + 1)';
const String _key = '2';
const List<String> _options = [_key, '11', 'Error'];

/// The opening line of the open-quiz instruction (`openQuizDirective`).
const String _guard = 'OPEN QUIZ — STRICT.';

String _quizReply() => llmEnvelope(
  text: _prompt,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': _code,
    'options': [
      for (final o in _options) {'option': o},
    ],
    'correct': 'A',
  }),
);

String _answerReply(String text) =>
    llmEnvelope(text: text, meta: '{"type":"answer"}');

String _gradeReply(String text) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'correct',
    'loSignals': <Object>[],
  }),
);

/// Fresh finders per call: a reused instance caches elements that a mode
/// swap has since unmounted (#133).
Finder _panel() => find.byKey(const Key('chat-panel'));
Finder _strip() => find.byKey(const Key('chat-expand'));
Finder _stripAvatar() =>
    find.descendant(of: _strip(), matching: find.byType(TutorAvatar));
Finder _composer() => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);
Finder _promptText() => find.textContaining(_prompt, findRichText: true);

double _panelWidth(WidgetTester tester) => tester.getSize(_panel()).width;
double _sessionWidth(WidgetTester tester) =>
    tester.getSize(find.byType(SessionView)).width;

void _resize(WidgetTester tester, double width) {
  tester.view.physicalSize =
      Size(width, _laptop.height) * tester.view.devicePixelRatio;
}

/// "Try it yourself", spelled out or, in the narrowest footer, its arrow.
Finder _tryIt() {
  final word = find.text('Try it yourself');
  return word.evaluate().isNotEmpty ? word : find.byTooltip('Try it yourself');
}

/// The quiz whole inside its column: no overflow anywhere, and every word,
/// icon and option tile of it between the column's edges. (The quiz
/// scrolls, so the bottom of the column is not a limit.)
void _quizLaidOut(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: where);
  final column = tester.getRect(find.byType(PracticeView));
  final chat = tester.getRect(_panel());
  expect(column.right, lessThanOrEqualTo(chat.left + 0.01), reason: where);
  final parts = find.descendant(
    of: find.byType(QuizView),
    matching: find.byWidgetPredicate(
      (w) => w is Text || w is RichText || w is Icon || w is AnimatedContainer,
    ),
  );
  expect(parts, findsWidgets, reason: where);
  for (final part in parts.evaluate()) {
    final box = part.renderObject! as RenderBox;
    final r = box.localToGlobal(Offset.zero) & box.size;
    expect(
      r.left >= column.left - 0.01 && r.right <= column.right + 0.01,
      isTrue,
      reason: '$where: ${part.widget.runtimeType} at $r, column $column',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('on a student laptop the chat is there while a quiz is open: '
      'a question next to it or on the theory page is a question, never the '
      'answer, and the pick is graded as always', (tester) async {
    final llm = ScriptedLlm([
      _quizReply(),
      _answerReply('Look at what + does with two numbers.'),
      _answerReply('The quotes make it text.'),
      _gradeReply('Right: 1 + 1 is 2.'),
    ]);
    final harness = AppHarness(
      llm: llm,
      windowSize: _laptop,
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
    ActiveMcq? quiz() => harness.container.read(activeMcqProvider);

    // The lesson on the laptop: the chat folded to the strip (#138), which
    // shows the tutor, not a chevron.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntil(
      tester,
      () => harness.lessonRunner.ran.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page never loaded',
    );
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatCollapsedWidth,
      reason: 'the chat did not start folded on the laptop',
    );
    expect(_stripAvatar(), findsOneWidget);
    expect(
      find.descendant(of: _panel(), matching: find.byIcon(Icons.chevron_left)),
      findsNothing,
    );
    expect(find.byTooltip('Show chat'), findsOneWidget);

    // Practice: the quiz, and the full chat next to it.
    await tester.tap(_tryIt());
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, _promptText());
    await sent(1);
    await idle();
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatPanelWidth,
      reason: 'the chat never slid open next to the quiz',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getSize(find.byType(PracticeView)).width,
      _sessionWidth(tester) - chatPanelWidth,
    );
    _quizLaidOut(tester, 'quiz at ${_laptop.width} px');
    final shown = quiz()!.options;

    // A question next to the quiz.
    await typeInChat(tester, 'What does the + do here?');
    await sent(2);
    final asked = request(1);
    expect(asked['request_type'], 'student_question');
    expect(asked['question'], 'What does the + do here?');
    expect(asked['open_quiz'], {
      'question': _prompt,
      'code': _code,
      'options': {for (var i = 0; i < shown.length; i++) 'ABC'[i]: shown[i]},
    });
    expect(asked.containsKey('correct_option'), isFalse);
    expect(llm.sentInstructions[1], contains(_guard));
    await pumpUntilFound(
      tester,
      find.textContaining('what + does', findRichText: true),
    );
    await idle();
    expect(quiz()?.selected, isNull, reason: 'the quiz still waits');
    expect(find.byType(QuizView), findsOneWidget);
    expect(harness.cosmos['turn_history'].docs, isEmpty);

    // The theory with the quiz pending: the strip is there, and a question
    // is about the page.
    await tester.tap(find.text('Explain'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntilGone(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatCollapsedWidth,
      reason: 'the chat is not on the theory page with a quiz pending',
    );
    expect(_stripAvatar(), findsOneWidget);
    await tester.tap(_stripAvatar());
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatPanelWidth,
      reason: 'the strip did not open the chat',
    );
    await pumpUntilFound(
      tester,
      find.text('Ask a question about this explanation…'),
    );
    await typeInChat(tester, 'Why are there quotes?');
    await sent(3);
    final aboutPage = request(2);
    expect(aboutPage['request_type'], 'content_question');
    expect(aboutPage['content_title'], 'Print');
    expect(llm.sentInstructions[2], contains(_guard));
    await pumpUntilFound(
      tester,
      find.textContaining('make it text', findRichText: true),
    );
    await idle();
    expect(quiz()?.selected, isNull);
    expect(harness.cosmos['turn_history'].docs, isEmpty);

    // Back to the quiz: the same one, and the pick is graded with its key.
    await tester.tap(_tryIt());
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilGone(tester, find.byType(ExplainView));
    expect(llm.sends, 3, reason: 'practice asked for a new exercise');
    await pumpUntilFound(tester, _promptText());
    await tester.tap(
      find.descendant(of: find.byType(QuizView), matching: find.text(_key)),
    );
    await sent(4);
    final pick = request(3);
    expect(pick['request_type'], 'mcq_answer');
    expect(pick['answer'], _key);
    expect(pick['correct_option'], _key);
    expect(llm.sentInstructions[3], isNot(contains(_guard)));
    await pumpUntilFound(
      tester,
      find.textContaining('1 + 1 is 2', findRichText: true),
    );
    await idle();
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == 1,
      reason: 'the pick was not recorded',
    );
    expect(harness.container.read(modeProvider), SessionMode.practice);
    await tester.pump(const Duration(milliseconds: 400));
    _quizLaidOut(tester, 'graded quiz at ${_laptop.width} px');

    // Made 700 px wide: the chat takes half the session, the quiz the other
    // half — feedback and "Next" included.
    _resize(tester, _narrow);
    await tester.pump();
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == _sessionWidth(tester) / 2,
      reason: 'the chat never settled at half the session',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getSize(find.byType(PracticeView)).width,
      _sessionWidth(tester) / 2,
    );
    _quizLaidOut(tester, 'graded quiz at $_narrow px');
    expect(llm.remaining, 0);

    await harness.dispose(tester);
  });
}
