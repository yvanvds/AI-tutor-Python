// End-to-end (#216): the question's short ID, from the student's screen to
// the teacher's Questions page.
//
// A teacher who sees a question on a student's screen that is off must find
// it again in the bank. So the header of every exercise that is a question
// shows its short ID — `#` and the first six characters of its content hash,
// small, muted, monospace — next to the quiz pill, or on the strip above the
// editor of a code exercise; not in the chat. A generated question shows it
// from the start, before the bank has it (#215: the bank keeps it only when
// its first answer is correct); one from the bank shows the bank's.
//
// On the Questions page "Find by ID" takes that ID as the student reads it
// out — with or without `#`, in capitals — or a whole doc id: the subgoal is
// selected in the tree and the card put on top, marked. An ID on two
// subgoals finds both; one the bank does not have says why that usually is.
//
// Next to every ID a small button copies it (#304), `#` and all, and shows
// for a moment that it did: in the quiz header, on the strip above the
// editor and on the teacher's card. What is copied, pasted into "Find by
// ID", finds the question. The header and the strip still fit with the chat
// open in a 700 px window. The real clipboard, the real font, the real
// window made narrow; there the Run button drops its shortcut hint to make
// room.
//
// Real app, real navigation, real quiz, practice and Questions views, real
// tutor → question bank service → in-memory Cosmos; only the model is
// scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/question_id.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/questions/questions_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/question_id_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _prompt = 'Wat drukt print(1 + 1) af?';
const String _right = '2';
const String _wrong = '11';
const String _codePrompt = 'Geef naam een waarde.';
const String _code = 'naam = ___';

/// The multiple-choice question as the app parses it from [_mcqReply].
final MultipleChoice _mcq = MultipleChoice(
  type: 'multiple_choice',
  prompt: _prompt,
  code: 'print(1 + 1)',
  options: const [_right, _wrong, 'Error'],
  correct: _right,
);

/// The complete-code question as the app parses it from its reply.
final CompleteCode _completeCode = CompleteCode(
  type: 'complete_code',
  prompt: _codePrompt,
  code: _code,
);

String _mcqReply() => llmEnvelope(
  text: _prompt,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': 'print(1 + 1)',
    'options': [
      {'option': _right},
      {'option': _wrong},
      {'option': 'Error'},
    ],
    'correct': 'A',
  }),
);

String _wrongGrade() => llmEnvelope(
  text: 'Nee: 1 + 1 is een som, geen tekst.',
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'wrong',
    'loSignals': <Object>[],
  }),
);

/// The short ID the app shows for [response], wherever it is asked.
String _shortIdOf(ChatResponse response) =>
    BankQuestion.shortIdOf(BankQuestion.contentHashOf(response)!);

/// [response] as another student's app stored it on [subgoalId].
BankQuestion _stored(ChatResponse response, {String subgoalId = 's1'}) =>
    BankQuestion.fromResponse(
      response,
      subgoalId: subgoalId,
      rootGoalId: 'r1',
      targetLOIds: [subgoalId == 's1' ? 'lo-print' : 'lo-var'],
      difficulty: QuestionDifficulty.medium,
      language: 'en',
      model: 'gpt-5-mini',
      createdByUid: 'another-student',
      createdAt: DateTime.utc(2026, 9, 20),
    )!;

Map<String, dynamic> _bankDoc(
  BankQuestion q, {
  String? createdAt,
  int asked = 1,
  int answered = 1,
  int correct = 1,
}) => {
  ...q.toMap(),
  'createdAt': ?createdAt,
  'askedCount': asked,
  'answeredCount': answered,
  'correctCount': correct,
  'lastAskedAt': '2026-09-21T10:00:00.000Z',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final quizId = find.byKey(const Key('quiz-question-id'));
  final exerciseId = find.byKey(const Key('exercise-question-id'));

  String idText(WidgetTester tester, Finder tag) => tester
      .widget<Text>(find.descendant(of: tag, matching: find.byType(Text)))
      .data!;

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      );

  /// Leerpad → theory → "Try it yourself": the practice view asks for an
  /// exercise on mount.
  Future<void> practise(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
  }

  List<Map<String, dynamic>> turns(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList();

  Finder copyOf(Finder tag) =>
      find.descendant(of: tag, matching: find.byKey(QuestionIdTag.copyKey));

  /// Clicks the copy button of [tag] (#304): returns what is on the real
  /// clipboard, once the button shows its check; the button sits right of
  /// the ID, on its line.
  Future<String?> copy(WidgetTester tester, Finder tag) async {
    final button = copyOf(tag);
    expect(button, findsOneWidget);
    final id = tester.getRect(
      find.descendant(of: tag, matching: find.byType(Text)),
    );
    final at = tester.getRect(button);
    expect(at.left, greaterThanOrEqualTo(id.right));
    expect(at.left - id.right, lessThan(6));
    expect((at.center.dy - id.center.dy).abs(), lessThan(3));
    await Clipboard.setData(const ClipboardData(text: 'not the ID'));

    await tester.tap(button);
    await pumpUntilFound(
      tester,
      find.descendant(of: button, matching: find.byIcon(Icons.check_rounded)),
    );
    expect(
      find.ancestor(of: button, matching: find.byTooltip('Copied')),
      findsOneWidget,
    );
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    // And back to the copy icon after a moment.
    await pumpUntilFound(
      tester,
      find.descendant(of: button, matching: find.byIcon(Icons.copy_rounded)),
    );
    expect(
      find.ancestor(of: button, matching: find.byTooltip('Copy the ID')),
      findsOneWidget,
    );
    return data?.text;
  }

  /// The window made 700 px wide. Outside the theory view the chat stays
  /// open: it takes half the session, and half is left for the exercise.
  Future<void> narrowWithChat(WidgetTester tester) async {
    tester.view.physicalSize =
        Size(700, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
    await pumpUntil(
      tester,
      () =>
          (tester.getSize(find.byKey(const Key('chat-panel'))).width -
                  tester.getSize(find.byType(SessionView)).width / 2)
              .abs() <
          0.5,
      reason: 'the chat never took half the session',
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> wideAgain(WidgetTester tester) async {
    tester.view.physicalSize = kRunnerWindowSize * tester.view.devicePixelRatio;
    await pumpUntil(
      tester,
      () =>
          tester.getSize(find.byKey(const Key('chat-panel'))).width ==
          chatPanelWidth,
      reason: 'the chat never grew back',
    );
  }

  /// Every word and icon of [of] whole inside [outer].
  void partsInside(WidgetTester tester, Finder of, Rect outer, String where) {
    final parts = find.descendant(
      of: of,
      matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
    );
    expect(parts, findsWidgets, reason: where);
    for (final part in parts.evaluate()) {
      final box = part.renderObject! as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      expect(
        r.left >= outer.left - 0.01 &&
            r.top >= outer.top - 0.01 &&
            r.right <= outer.right + 0.01 &&
            r.bottom <= outer.bottom + 0.01,
        isTrue,
        reason: '$where: ${part.widget} at $r, outside $outer',
      );
    }
  }

  testWidgets('a generated question shows its short ID in the header of the '
      'exercise from the start — before the bank has it — and the next '
      'exercise its own, on the strip above the editor; not in the chat', (
    tester,
  ) async {
    final llm = ScriptedLlm([
      _mcqReply(),
      _wrongGrade(),
      completeCodeReply(text: _codePrompt, code: _code),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
    await pumpUntilFound(tester, quizId);

    final mcqId = _shortIdOf(_mcq);
    expect(mcqId, matches(RegExp(r'^#[0-9a-f]{6}$')));
    expect(idText(tester, quizId), mcqId);
    expect(harness.cosmos['questions'].docs, isEmpty, reason: 'not stored');
    // Next to the pill, on its line, and nowhere else.
    final pill = tester.getRect(find.text('QUIZ QUESTION'));
    final tag = tester.getRect(quizId);
    expect(tag.left, greaterThan(pill.right));
    expect((tag.center.dy - pill.center.dy).abs(), lessThan(4));
    expect(find.text(mcqId), findsOneWidget);
    // Its button copies it as it is shown (#304).
    expect(await copy(tester, quizId), mcqId);

    // Answered wrong, so never stored: the ID stays with the question on
    // screen, and it is the one its turn record names.
    await waitForIdle(tester, harness);
    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining('1 + 1 is een som', findRichText: true),
    );
    await waitForIdle(tester, harness);
    expect(idText(tester, quizId), mcqId);
    await pumpUntil(tester, () => turns(harness).length == 1);
    expect(
      BankQuestion.shortIdOf(turns(harness).single['questionId'] as String),
      mcqId,
    );
    expect(harness.cosmos['questions'].docs, isEmpty);

    // "Next": a code exercise, with its own ID above the editor.
    await tester.tap(find.text('Next →'));
    await pumpUntil(
      tester,
      () =>
          find.byType(CodeField).evaluate().isNotEmpty &&
          editorText(tester) == _code,
      timeout: const Duration(seconds: 30),
      reason: 'the code exercise never reached the editor',
    );
    await waitForIdle(tester, harness);
    await pumpUntilFound(tester, exerciseId);
    final codeId = _shortIdOf(_completeCode);
    expect(idText(tester, exerciseId), codeId);
    expect(codeId, isNot(mcqId));
    expect(
      find.descendant(of: find.byType(RunControls), matching: exerciseId),
      findsOneWidget,
    );
    expect(quizId, findsNothing);
    expect(find.text(mcqId), findsNothing);
    // The question itself is in the chat; its ID is not.
    expect(
      find.descendant(
        of: find.byType(ChatWidget),
        matching: find.textContaining(_codePrompt, findRichText: true),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(ChatWidget),
        matching: find.textContaining(codeId, findRichText: true),
      ),
      findsNothing,
    );
    expect(find.text(codeId), findsOneWidget);
    expect(await copy(tester, exerciseId), codeId);

    // In a 700 px window with the chat open the strip still holds it all:
    // Run and Reset, the ID with its button, hint and send (#304).
    await narrowWithChat(tester);
    expect(tester.takeException(), isNull, reason: 'the strip at 700 px');
    final exercise = tester.getRect(find.byType(PracticeView));
    final controls = tester.getRect(find.byType(RunControls));
    expect(controls.left, greaterThanOrEqualTo(exercise.left));
    expect(controls.right, lessThanOrEqualTo(exercise.right + 0.01));
    partsInside(tester, find.byType(RunControls), controls, 'strip, 700 px');
    expect(idText(tester, exerciseId), codeId);
    final strip =
        [
          find.text('Run'),
          find.byTooltip('Reset output'),
          exerciseId,
          find.byTooltip('Ask for a hint'),
          find.byTooltip('Send to tutor'),
        ].map((f) {
          final inStrip = find.descendant(
            of: find.byType(RunControls),
            matching: f,
          );
          expect(inStrip, findsOneWidget, reason: '$f');
          return tester.getRect(inStrip);
        }).toList();
    for (var i = 1; i < strip.length; i++) {
      expect(
        strip[i].left,
        greaterThanOrEqualTo(strip[i - 1].right - 0.01),
        reason: 'part $i of the strip runs into the one before: $strip',
      );
    }
    // Run made room by putting its shortcut hint in its tooltip.
    expect(find.byKey(const Key('run-shortcut-hint')), findsNothing);
    expect(await copy(tester, exerciseId), codeId);
    await wideAgain(tester);
    expect(find.byKey(const Key('run-shortcut-hint')), findsOneWidget);

    expect(llm.remaining, 0);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('a question from the bank shows the bank\'s ID', (tester) async {
    final served = _stored(_mcq);
    // Any call fails loudly: the question must come from the bank.
    final llm = ScriptedLlm(const []);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        // A `predict` LO, so the conductor plans a multiple-choice question.
        'goals': [
          goalDoc(
            id: 's1',
            title: 'Print',
            parentId: 'r1',
            order: 1000,
            contentId: 's1',
            objectives: [
              {
                ...objective('lo-print', 'Use print() to show text'),
                'kind': 'predict',
              },
            ],
          ),
        ],
        'config': [
          {
            'id': 'global',
            'type': 'config',
            'Model': 'gpt-4o',
            'ApiKey': '',
            'QuestionBankMinimum': 1,
            'QuestionBankShare': 1.0,
          },
        ],
        'questions': [_bankDoc(served)],
      },
    );
    await harness.boot(tester);
    await pumpUntil(
      tester,
      () =>
          harness.container
              .read(globalConfigServiceProvider)
              ?.questionBankShare ==
          1.0,
      reason: 'config/global never reached the app',
    );

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
    await waitForIdle(tester, harness);
    expect(llm.sends, 0, reason: 'served from the bank');

    expect(idText(tester, quizId), served.shortId);
    expect(served.shortId, _shortIdOf(_mcq));

    // In a 700 px window with the chat open the header holds the pill, the
    // ID and its button, which still copies (#304).
    await narrowWithChat(tester);
    expect(tester.takeException(), isNull, reason: 'the quiz at 700 px');
    final quiz = tester.getRect(find.byType(QuizView));
    final pill = tester.getRect(find.text('QUIZ QUESTION'));
    final tag = tester.getRect(quizId);
    expect(pill.left, greaterThanOrEqualTo(quiz.left));
    expect(tag.left, greaterThan(pill.right));
    expect(tag.right, lessThanOrEqualTo(quiz.right));
    expect((tag.center.dy - pill.center.dy).abs(), lessThan(4));
    partsInside(tester, quizId, quiz, 'quiz header, 700 px');
    expect(await copy(tester, quizId), served.shortId);
    await wideAgain(tester);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('the teacher finds a question by the ID the student reads out: '
      'its subgoal selected, the card on top and marked; an ID on two '
      'subgoals finds both; one the bank does not have says why', (
    tester,
  ) async {
    final wanted = _stored(_mcq);
    // The same question, also stored on another subgoal: the same short ID.
    final twin = _stored(_mcq, subgoalId: 's2');
    // Newer questions of the same subgoal, first on "Newest".
    final newer = [
      _stored(_completeCode),
      _stored(
        CompleteCode(
          type: 'complete_code',
          prompt: 'Maak x vijf.',
          code: 'x = ___',
        ),
      ),
    ];
    // Answered wrong first, so never stored (#215).
    final neverKept = _shortIdOf(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: 'En print(2 * 3)?',
        code: 'print(2 * 3)',
        options: const ['6', '23'],
        correct: '6',
      ),
    );
    expect(
      [wanted, ...newer].map((q) => q.shortId),
      isNot(contains(neverKept)),
    );
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'questions': [
          _bankDoc(wanted),
          _bankDoc(twin),
          for (final q in newer)
            _bankDoc(q, createdAt: '2026-09-28T10:00:00.000Z'),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Questions'));
    await pumpUntilFound(tester, find.byType(QuestionsPage));
    await pumpUntilFound(tester, find.byKey(const Key('questions-tree')));

    final field = find.byKey(const Key('questions-lookup'));
    Future<void> lookUp(String typed, {bool enter = true}) async {
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, typed);
      await tester.pump();
      if (enter) {
        await tester.testTextInput.receiveAction(TextInputAction.search);
      } else {
        await tester.tap(find.byKey(const Key('questions-lookup-go')));
      }
      await tester.pump();
    }

    bool selected(String subgoalId) => tester
        .widget<ListTile>(find.byKey(Key('questions-subgoal-$subgoalId')))
        .selected;
    Finder card(BankQuestion q) => find.byKey(Key('questions-card-${q.id}'));
    Finder found(BankQuestion q) => find.byKey(Key('questions-found-${q.id}'));
    final list = find.byKey(const Key('questions-list'));

    /// Whether [q]'s card is the first of the list. The cards further down
    /// are not built in a 720-pixel window.
    bool onTop(BankQuestion q) =>
        card(q).evaluate().isNotEmpty &&
        (tester.getTopLeft(card(q)).dy - tester.getTopLeft(list).dy).abs() < 1;

    // "Newest" first, as the page opens a subgoal: the question the teacher
    // is after is not on top. Every card shows its own ID.
    await tester.tap(find.byKey(const Key('questions-subgoal-s1')));
    await pumpUntil(tester, () => newer.any(onTop));
    expect(onTop(wanted), isFalse);
    final first = newer.firstWhere(onTop);
    expect(
      idText(tester, find.byKey(Key('questions-id-${first.id}'))),
      first.shortId,
    );

    // As the student reads it out: in capitals, with `#`. The question is
    // on two subgoals: both are found, the first one is shown — on top of
    // its subgoal's list, marked, with its ID.
    await lookUp(wanted.shortId.toUpperCase());
    await pumpUntilFound(tester, found(wanted));
    await pumpUntil(tester, () => onTop(wanted));
    expect(selected('s1'), isTrue);
    expect(selected('s2'), isFalse);
    expect(
      idText(tester, find.byKey(Key('questions-id-${wanted.id}'))),
      wanted.shortId,
    );
    for (final q in newer) {
      expect(found(q), findsNothing);
    }
    final several = find.byKey(const Key('questions-lookup-several'));
    expect(
      find.descendant(
        of: several,
        matching: find.text('2 questions have this ID:'),
      ),
      findsOneWidget,
    );

    // To the other subgoal it is on.
    await tester.tap(find.byKey(const Key('questions-lookup-subgoal-s2')));
    await pumpUntilFound(tester, found(twin));
    expect(selected('s2'), isTrue);
    expect(selected('s1'), isFalse);

    // The whole doc id names one; the search button does what Enter does.
    await lookUp(wanted.id, enter: false);
    await pumpUntil(tester, () => selected('s1'));
    await pumpUntilFound(tester, found(wanted));
    await pumpUntilGone(tester, several);

    // The button on the card copies the ID (#304); pasted into the field it
    // finds the question again — on both subgoals, as the short ID does.
    final pasted = await copy(
      tester,
      find.byKey(Key('questions-id-${wanted.id}')),
    );
    expect(pasted, wanted.shortId);
    await lookUp(pasted!);
    await pumpUntilFound(tester, several);
    await pumpUntilFound(tester, found(wanted));
    expect(selected('s1'), isTrue);

    // One the bank does not have: why that usually is.
    final miss = find.byKey(const Key('questions-lookup-miss'));
    await lookUp(neverKept);
    await pumpUntilFound(tester, miss);
    expect(
      tester.widget<Text>(miss).data,
      'This question is not in the bank. Usually the first answer to it was '
      'not (fully) correct, and then a question is not kept. Or it was '
      'deleted.',
    );
    await lookUp('#ab');
    await pumpUntil(
      tester,
      () =>
          miss.evaluate().isNotEmpty &&
          tester.widget<Text>(miss).data!.startsWith('That is not'),
    );
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
