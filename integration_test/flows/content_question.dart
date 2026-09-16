// End-to-end (#132): a question typed while a theory page is on screen is
// answered about that page. Sam has a practice question waiting in the chat
// (an `explain_code` probe, answered by typing), goes back to the theory to
// read up, and types a question there. It used to land in the grader as the
// answer to the pending probe; now it goes out as a `content_question` that
// carries the page — title and body as text — and comes back as a plain
// answer in the chat, while the probe stays pending: back in practice, the
// next thing Sam types is graded against it exactly as before. The
// composer says so: its hint names the page while the page is in scope.
//
// The second test pages back (#115): the page sent is the one on screen,
// not the active subgoal's, and the prompt is written for that older
// subgoal.
//
// Real app, real navigation, real theory view over the real Windows
// WebView, real chat composer, real TutorService → routing → prompt
// assembly. Only the model is scripted (`ScriptedLlm`), and what a flow
// asserts on is what the running app *sent* it.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/content_question.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kPageHint = 'Ask a question about this explanation…';
const String kPlainHint = 'Type your question or answer…';

const String kProbeCode = 'naam = "Mira"\nprint("Hallo", naam)';
const String kNextProbeCode = 'print(1, 2)';

/// An `explain_code` probe: the code goes to the editor, the question to the
/// chat, and the student answers by typing — the kind of pending question a
/// theory-page question used to be graded as.
String explainCodeReply({required String text, required String code}) =>
    llmEnvelope(
      text: text,
      meta: jsonEncode({'type': 'explain_code', 'code': code}),
    );

String explainFeedbackReply({required String text}) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'explain_feedback',
    'overallQuality': 'correct',
    'loSignals': [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  }),
);

String answerReply(String text) =>
    llmEnvelope(text: text, meta: '{"type":"answer"}');

/// "Print" with a `reason` objective, so the conductor's cold start asks an
/// `explain_code` question — one the student answers in the chat.
Map<String, List<Map<String, dynamic>>> reasonOnPrint() => {
  'goals': [
    goalDoc(
      id: 's1',
      title: 'Print',
      parentId: 'r1',
      order: 1000,
      contentId: 's1',
      objectives: [
        {
          'id': 'lo-print',
          'statement': 'Explain what print() shows',
          'kind': 'reason',
          'weight': 1.0,
          'optional': false,
        },
      ],
    ),
  ],
};

/// The Python inside the Variables lesson's live-preview block — distinct
/// from `kLessonExampleCode`, so the runner tells the two pages apart.
const String kVariablesExampleCode = 'stad = "Gent"\nprint(stad)';

const String kVariablesBody =
    '<h2>Variables</h2>'
    '<p>Een naam voor een waarde.</p>'
    '<pre class="run"><code>$kVariablesExampleCode</code></pre>';

/// "Print" is done, so the conductor lands the student on "Variables" —
/// which carries a lesson of its own to page back from.
Map<String, List<Map<String, dynamic>>> onVariables() => {
  'progress': [
    {
      'id': '${kStudentUid}_s1',
      'uid': kStudentUid,
      'goalId': 's1',
      'progress': 1.0,
      'updatedAt': '2026-07-20T10:00:00Z',
      'lastSessionAt': '2026-07-20T10:00:00Z',
    },
  ],
  'goals': [
    goalDoc(
      id: 's2',
      title: 'Variables',
      parentId: 'r1',
      order: 2000,
      contentId: 's2',
      objectives: [objective('lo-var', 'Assign a value to a name')],
    ),
  ],
  'content': [
    {
      'id': 's2',
      'type': 'content',
      'title': 'Variables',
      'body': kVariablesBody,
      'updatedAt': '2026-05-01T10:00:00Z',
    },
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// The composer's field. A fresh finder per call: a mode swap unmounts
  /// the composer and a reused instance would hold the old element (#133).
  Finder composer() => find.descendant(
    of: find.byType(ComposerIdle),
    matching: find.byType(TextField),
  );

  /// Clicks into the composer, types, and presses send. The click is what
  /// a student does, and it is load-bearing here: `enterText` alone focuses
  /// a field only through `binding.focusedEditable`, which is a no-op when
  /// that already names this field from the previous message — the
  /// composer keeps its state across the tutor's working phase, so the
  /// second message of a flow would go nowhere.
  Future<void> typeInChat(WidgetTester tester, String text) async {
    await pumpUntilFound(tester, composer());
    await tester.tap(composer());
    await tester.pump();
    await tester.enterText(composer(), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
  }

  Future<void> lessonOnScreen(
    WidgetTester tester,
    AppHarness harness,
    String code,
  ) => pumpUntil(
    tester,
    () =>
        harness.lessonRunner.ran.isNotEmpty &&
        harness.lessonRunner.ran.last == code,
    timeout: const Duration(seconds: 30),
    reason: 'the lesson page with "$code" never loaded',
  );

  Future<void> openLesson(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
  }

  Future<void> sent(WidgetTester tester, ScriptedLlm llm, int count) =>
      pumpUntil(
        tester,
        () => llm.sends == count,
        timeout: const Duration(seconds: 30),
        reason: 'the app never sent request $count',
      );

  Map<String, dynamic> request(ScriptedLlm llm, int i) =>
      jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;

  testWidgets('a question typed on the theory page goes out with the page '
      'and comes back as an answer; the pending practice question is still '
      'graded when the student comes back and answers it', (tester) async {
    final llm = ScriptedLlm([
      explainCodeReply(text: 'What does this print?', code: kProbeCode),
      answerReply('The comma makes print show both values with a space.'),
      explainFeedbackReply(text: 'Exactly right.'),
      explainCodeReply(text: 'And this one?', code: kNextProbeCode),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: reasonOnPrint(),
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);
    await openLesson(tester);
    await lessonOnScreen(tester, harness, kLessonExampleCode);

    // The theory view with its page: the composer says a question is about
    // it.
    await pumpUntilFound(tester, find.text(kPageHint));
    expect(find.text(kPlainHint), findsNothing);

    // Into practice: the probe arrives, in the editor and in the chat, and
    // the hint is the usual one — what is typed here answers the probe.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await sent(tester, llm, 1);
    await pumpUntil(
      tester,
      () => editorText(tester) == kProbeCode,
      timeout: const Duration(seconds: 30),
      reason: 'the probe never reached the editor',
    );
    expect(
      find.textContaining('What does this print?', findRichText: true),
      findsOneWidget,
    );
    await pumpUntilFound(tester, find.text(kPlainHint));
    expect(find.text(kPageHint), findsNothing);

    // Back to the theory to read up, and a question about it.
    await tester.tap(find.text('Explain'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntilGone(tester, find.byType(PracticeView));
    await pumpUntilFound(tester, find.text(kPageHint));
    await typeInChat(tester, 'Why is there a comma?');
    await sent(tester, llm, 2);

    final question = request(llm, 1);
    expect(
      question['request_type'],
      'content_question',
      reason:
          'the question on the theory page went out as ${question['request_type']}',
    );
    expect(question['question'], 'Why is there a comma?');
    expect(question['content_title'], 'Print');
    final page = question['content'] as String;
    expect(page, contains('## Print'));
    expect(page, contains('Zo toon je iets op het scherm.'));
    expect(page, contains('```\n$kLessonExampleCode\n```'));
    expect(page, contains('print("geen preview")'));
    expect(page, isNot(contains('<')), reason: 'markup in the page text');
    expect(question.containsKey('answer'), isFalse);
    expect(question.containsKey('target_los'), isFalse);
    // The prompt: the built-in content-question body (no teacher doc in the
    // seed), written for the page's subgoal.
    expect(llm.sentInstructions[1], contains('### CONTENT QUESTION'));
    expect(
      llm.sentInstructions[1],
      contains('belongs to the subgoal "Print" of the goal "Basics"'),
    );

    // The answer is in the chat; nothing was graded.
    await pumpUntilFound(
      tester,
      find.textContaining('makes print show both values', findRichText: true),
    );
    expect(harness.cosmos['turn_history'].docs, isEmpty);
    expect(harness.cosmos['lo_beliefs'].docs, isEmpty);

    // Back in practice the probe is still the one in flight: same code in
    // the editor, and what Sam types now is graded against it.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilGone(tester, find.byType(ExplainView));
    expect(llm.sends, 2, reason: 'practice asked for a new exercise');
    expect(editorText(tester), kProbeCode);
    await pumpUntilFound(tester, find.text(kPlainHint));
    await typeInChat(tester, 'It prints Hallo and the name.');
    await sent(tester, llm, 4);

    final graded = request(llm, 2);
    expect(graded['request_type'], 'explain_answer');
    expect(graded['answer'], 'It prints Hallo and the name.');
    expect((graded['target_los'] as List).single['id'], 'lo-print');
    await pumpUntilFound(
      tester,
      find.textContaining('Exactly right.', findRichText: true),
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextProbeCode,
      timeout: const Duration(seconds: 30),
      reason: 'the next probe never reached the editor',
    );
    expect(llm.remaining, 0);
    expect(harness.cosmos['turn_history'].docs, hasLength(1));

    await harness.dispose(tester);
  });

  testWidgets('after paging back, the page sent is the one on screen and '
      'the prompt is written for its subgoal, not the active one', (
    tester,
  ) async {
    final llm = ScriptedLlm([answerReply('It shows the text on screen.')]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: onVariables(),
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
        kVariablesExampleCode: const LessonRunResult(stdout: 'Gent'),
      },
    );
    await harness.boot(tester);
    await openLesson(tester);
    await lessonOnScreen(tester, harness, kVariablesExampleCode);
    expect(
      harness.container.read(goalSelectionProvider).activeChildGoal?.id,
      's2',
    );

    await tester.tap(find.text('Previous'));
    await lessonOnScreen(tester, harness, kLessonExampleCode);
    expect(find.text('1 / 2'), findsOneWidget);

    await typeInChat(tester, 'What does this page explain?');
    await sent(tester, llm, 1);

    final question = request(llm, 0);
    expect(question['request_type'], 'content_question');
    expect(question['content_title'], 'Print');
    expect(question['content'], contains('Zo toon je iets op het scherm.'));
    expect(question['content'], isNot(contains('Een naam voor een waarde')));
    expect(
      llm.sentInstructions.single,
      contains('belongs to the subgoal "Print" of the goal "Basics"'),
    );
    expect(llm.sentInstructions.single, isNot(contains('"Variables"')));
    await pumpUntilFound(
      tester,
      find.textContaining('shows the text on screen', findRichText: true),
    );
    // The tutor never moved.
    expect(
      harness.container.read(goalSelectionProvider).activeChildGoal?.id,
      's2',
    );

    await harness.dispose(tester);
  });
}
