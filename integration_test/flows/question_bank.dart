// End-to-end (#185, #215): the question bank.
//
// A generated question is stored in the `questions` container —
// deduplicated on its content, with what it was asked for — at the first
// graded answer to it, and only when that answer is correct (#215): a
// question answered wrong first, or left unanswered, never enters it. The
// answer is counted there, a multiple-choice pick with the feedback the
// student got on it, and the turn record names the question either way.
// The teacher gets a Questions page for what the students' answers did not
// weed out: per subgoal, each question as the student saw it, how often it
// was asked and how often answered right, sorted on that share, who hid it
// (the teacher, or the bank itself below half correct), with hide / show
// again and delete — and a warning on a question whose key a grading
// called wrong (#198). No "reviewed", no notes.
//
// And the bank is the one container the app runs without: until it is
// created (README step 3), a student practises as before and the teacher's
// page says what to create.
//
// Real app, real navigation, real tutor → question bank service → in-memory
// Cosmos; only the model is scripted. The missing container goes through the
// real REST client (`UnprovisionedCosmos`, #170).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/question_bank.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/questions/questions_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/unprovisioned_cosmos.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _prompt = 'Wat drukt print(1 + 1) af?';
const String _right = '2';
const String _wrong = '11';
const String _feedback = 'Nee: 1 + 1 is een som, geen tekst.';
const String _next = 'naam = ___';

/// The multiple-choice turn, with its key as the positional letter the
/// `mcQuestion` instructions ask for.
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

String _gradeReply({String text = _feedback, String quality = 'wrong'}) =>
    llmEnvelope(
      text: text,
      meta: jsonEncode({
        'type': 'mcq_feedback',
        'overallQuality': quality,
        'loSignals': <Object>[],
      }),
    );

const String _prompt2 = 'Wat drukt print("a" * 3) af?';
const String _right2 = 'aaa';
const String _feedback2 = 'Juist: * herhaalt de tekst.';

/// A second multiple-choice turn, answered right.
String _mcqReply2() => llmEnvelope(
  text: _prompt2,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': 'print("a" * 3)',
    'options': [
      {'option': _right2},
      {'option': 'a3'},
      {'option': 'Error'},
    ],
    'correct': 'A',
  }),
);

/// A bank doc as a student's app stores it, with the counts it has
/// gathered since.
Map<String, dynamic> _bankDoc(
  BankQuestion q, {
  int asked = 1,
  int answered = 0,
  int correct = 0,
}) => {
  ...q.toMap(),
  'askedCount': asked,
  'answeredCount': answered,
  'correctCount': correct,
};

BankQuestion _stored(ChatResponse response, {String subgoalId = 's1'}) =>
    BankQuestion.fromResponse(
      response,
      subgoalId: subgoalId,
      rootGoalId: 'r1',
      targetLOIds: [subgoalId == 's1' ? 'lo-print' : 'lo-var'],
      difficulty: QuestionDifficulty.medium,
      language: 'nl',
      model: 'gpt-5-mini',
      createdByUid: kStudentUid,
      createdAt: DateTime.utc(2026, 9, 23, 10),
    )!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Leerpad → theory → "Try it yourself": the exercise request plays the
  /// scripted multiple-choice turn and opens the quiz, with [option] on it.
  Future<void> openQuiz(WidgetTester tester, {String option = _wrong}) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(option));
  }

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      );

  /// Picks [option] on the quiz on screen and waits for [feedback].
  Future<void> pick(
    WidgetTester tester,
    AppHarness harness,
    String option,
    String feedback,
  ) async {
    await tester.tap(find.text(option));
    await pumpUntilFound(
      tester,
      find.textContaining(feedback, findRichText: true),
    );
    await waitForIdle(tester, harness);
  }

  /// "Next" to the complete-code turn, until it is in the editor.
  Future<void> nextToCode(WidgetTester tester) async {
    await tester.tap(find.text('Next →'));
    await pumpUntil(
      tester,
      () =>
          find.byType(CodeField).evaluate().isNotEmpty &&
          editorText(tester) == _next,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
  }

  testWidgets('a generated question enters the bank only when its first '
      'answer is correct — with what it was asked for, and the pick counted '
      'with the feedback the student got; one answered wrong or left '
      'unanswered never does, and the turn record names the question either '
      'way', (tester) async {
    final llm = ScriptedLlm([
      _mcqReply(),
      _gradeReply(),
      _mcqReply2(),
      _gradeReply(text: _feedback2, quality: 'correct'),
      completeCodeReply(text: 'Geef naam een waarde.', code: _next),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    final bank = harness.cosmos['questions'];
    List<Map<String, dynamic>> turns() =>
        harness.cosmos['turn_history'].docs.values.toList();

    // Answered wrong first: not stored.
    await openQuiz(tester);
    await pick(tester, harness, _wrong, '1 + 1 is een som');
    await pumpUntil(tester, () => turns().length == 1);
    final wrongId = turns().single['questionId'] as String;
    expect(wrongId, startsWith('s1_'));

    // Answered right first: stored.
    await tester.tap(find.text('Next →'));
    await pumpUntilFound(tester, find.text(_right2));
    await waitForIdle(tester, harness);
    await pick(tester, harness, _right2, '* herhaalt de tekst');
    await pumpUntil(
      tester,
      () => bank.docs.isNotEmpty,
      reason: 'the question answered right was not stored',
    );

    // Asked and left unanswered: not stored.
    await nextToCode(tester);
    expect(llm.remaining, 0);

    expect(bank.docs, hasLength(1));
    expect(bank[wrongId], isNull, reason: 'answered wrong first');
    final mcq = bank.docs.values.single;
    expect(mcq['id'], startsWith('s1_'));
    expect(mcq['questionType'], 'mcQuestion');
    expect(mcq['subgoalId'], 's1');
    expect(mcq['rootGoalId'], 'r1');
    expect(mcq['targetLOIds'], ['lo-print']);
    expect(mcq['difficulty'], 'medium');
    expect(mcq['language'], 'en');
    expect(mcq['createdByUid'], kStudentUid);
    expect(mcq['status'], 'active');
    // The question as the student got it, unshuffled, the key by content.
    expect(mcq['payload'], {
      'type': 'multiple_choice',
      'prompt': _prompt2,
      'code': 'print("a" * 3)',
      'options': [
        {'option': _right2},
        {'option': 'a3'},
        {'option': 'Error'},
      ],
      'correct': _right2,
    });
    expect(mcq['askedCount'], 1);
    expect(mcq['answeredCount'], 1);
    expect(mcq['correctCount'], 1);
    expect(mcq['lastAskedAt'], mcq['createdAt'], reason: 'asked, then stored');
    expect(mcq['optionFeedback'], [
      {'option': _right2, 'text': _feedback2, 'quality': 'correct'},
    ]);
    expect(mcq.containsKey('reviewedAt'), isFalse);

    // The turn records name the questions they graded, stored or not.
    expect(turns().map((t) => t['questionId']), [wrongId, mcq['id']]);

    await harness.dispose(tester);
  });

  testWidgets('without a `questions` container the student practises as '
      'before, and nothing is stored', (tester) async {
    final llm = ScriptedLlm([
      _mcqReply2(),
      _gradeReply(text: _feedback2, quality: 'correct'),
      completeCodeReply(text: 'Geef naam een waarde.', code: _next),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    // The live account before the teacher creates it: every other container
    // exists, `questions` does not.
    final missing = UnprovisionedCosmos('questions');
    harness.cosmos.route('questions', missing.container);

    // Answered right: the bank is asked to store it, and is not there.
    await openQuiz(tester, option: _right2);
    await pick(tester, harness, _right2, '* herhaalt de tekst');
    await nextToCode(tester);
    expect(llm.remaining, 0);

    // Nothing about the bank reaches the student.
    expect(find.textContaining('went wrong'), findsNothing);
    expect(tester.takeException(), isNull);
    // The turn record is written all the same, and still names the question:
    // its id is a content hash, and the bank finds it once it exists.
    final turns = harness.cosmos['turn_history'].docs.values.toList();
    expect(turns, hasLength(1));
    expect(turns.single['questionId'], startsWith('s1_'));
    expect(missing.requests, isNotEmpty);
    expect(missing.writes, isEmpty);
    expect(harness.cosmos['questions'].docs, isEmpty);

    await harness.dispose(tester);
  });

  testWidgets('the teacher weeds out the bank: a count and a hidden count per '
      'subgoal, each question as the student saw it, sorted on the share '
      'correct, who hid it; hide, show again a question that hid itself, and '
      'delete after a confirmation', (tester) async {
    final hard = _stored(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: _prompt,
        code: 'print(1 + 1)',
        options: const [_right, _wrong],
        correct: _right,
      ),
    );
    final easy = _stored(
      CompleteCode(
        type: 'complete_code',
        prompt: 'Toon een groet.',
        code: 'print(___)',
      ),
    );
    final other = _stored(
      CompleteCode(
        type: 'complete_code',
        prompt: 'Maak x vijf.',
        code: 'x = ___',
      ),
      subgoalId: 's2',
    );
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'questions': [
          _bankDoc(hard, asked: 6, answered: 5, correct: 1),
          _bankDoc(easy, asked: 4, answered: 4, correct: 4),
          // Hidden by the bank itself: 3 of 10 correct.
          {
            ..._bankDoc(other, asked: 10, answered: 10, correct: 3),
            'status': 'hidden',
            'hiddenBy': 'auto',
            'hiddenAt': '2026-09-26T10:00:00.000Z',
          },
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Questions'));
    await pumpUntilFound(tester, find.byType(QuestionsPage));
    await pumpUntilFound(tester, find.byKey(const Key('questions-tree')));

    String subtitle(String subgoalId) => tester
        .widget<Text>(find.byKey(Key('questions-subgoal-count-$subgoalId')))
        .data!;
    String badge(BankQuestion q) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(Key('questions-hidden-${q.id}')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(subtitle('s1'), '2 questions');
    expect(subtitle('s2'), '1 question · 1 hidden');

    await tester.tap(find.byKey(const Key('questions-subgoal-s1')));
    await pumpUntilFound(tester, find.byKey(Key('questions-card-${hard.id}')));
    await pumpUntilFound(tester, find.byKey(Key('questions-card-${easy.id}')));

    // The question as the student got it, and its numbers.
    final card = find.byKey(Key('questions-card-${hard.id}'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    expect(
      inCard(find.textContaining(_prompt, findRichText: true)),
      findsOneWidget,
    );
    expect(inCard(find.text(_wrong)), findsOneWidget);
    expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(inCard(find.text('20% correct (1/5)')), findsOneWidget);
    expect(inCard(find.text('asked 6×')), findsOneWidget);

    double top(BankQuestion q) =>
        tester.getTopLeft(find.byKey(Key('questions-card-${q.id}'))).dy;

    // Lowest share first: the question most students get wrong on top.
    await tester.tap(find.byKey(const Key('questions-sort-shareAsc')));
    await pumpUntil(tester, () => top(hard) < top(easy));
    await tester.tap(find.byKey(const Key('questions-sort-shareDesc')));
    await pumpUntil(tester, () => top(easy) < top(hard));

    // No review step and no notes any more (#215).
    expect(find.text('Mark reviewed'), findsNothing);
    expect(find.text('Note'), findsNothing);

    // Hide the one that is too hard to be fair.
    await tester.tap(find.byKey(Key('questions-hide-${hard.id}')));
    await pumpUntilFound(
      tester,
      find.byKey(Key('questions-hidden-${hard.id}')),
    );
    expect(badge(hard), 'HIDDEN');
    final stored = harness.cosmos['questions'][hard.id]!;
    expect(stored['status'], 'hidden');
    expect(stored['hiddenBy'], 'teacher');
    expect(stored.containsKey('reviewedAt'), isFalse);
    expect(harness.cosmos['questions'].docs, hasLength(3));
    await pumpUntil(tester, () => subtitle('s1') == '2 questions · 1 hidden');

    // "Hidden only" keeps to it, to clear it out: delete, after a
    // confirmation.
    await tester.tap(find.byKey(const Key('questions-filter-hidden')));
    await pumpUntilGone(tester, find.byKey(Key('questions-card-${easy.id}')));
    expect(find.byKey(Key('questions-card-${hard.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('questions-delete-${hard.id}')));
    await pumpUntilFound(tester, find.text('Delete this question?'));
    await tester.tap(find.byKey(const Key('questions-delete-confirm')));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntilFound(tester, find.byKey(const Key('questions-list-empty')));
    expect(
      tester.widget<Text>(find.byKey(const Key('questions-list-empty'))).data,
      'No hidden questions for this subgoal.',
    );
    expect(harness.cosmos['questions'][hard.id], isNull);
    expect(harness.cosmos['questions'].docs, hasLength(2));
    expect(subtitle('s1'), '1 question');

    // The question that hid itself, shown again: kept, so it does not hide
    // itself at the next answer.
    await tester.tap(find.byKey(const Key('questions-subgoal-s2')));
    await pumpUntilFound(tester, find.byKey(Key('questions-card-${other.id}')));
    expect(badge(other), 'HIDDEN AUTOMATICALLY');
    expect(
      find.descendant(
        of: find.byKey(Key('questions-card-${other.id}')),
        matching: find.text('30% correct (3/10)'),
      ),
      findsOneWidget,
    );
    // ("Hidden only" is still on: shown again, it leaves the list.)
    await tester.tap(find.byKey(Key('questions-unhide-${other.id}')));
    await pumpUntilGone(tester, find.byKey(Key('questions-card-${other.id}')));
    final kept = harness.cosmos['questions'][other.id]!;
    expect(kept['status'], 'active');
    expect(kept['keptByTeacher'], isTrue);
    expect(kept.containsKey('hiddenBy'), isFalse);
    await pumpUntil(tester, () => subtitle('s2') == '1 question');

    await harness.dispose(tester);
  });

  testWidgets('a key the grading called wrong (#198) is flagged on the '
      'teacher\'s card, though every pick was graded as the key says', (
    tester,
  ) async {
    // As the students' apps left it: one wrong pick graded wrong — which
    // agrees with the key — and two gradings that called the key wrong.
    final disputed = _stored(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: 'Wat drukt print(2 * 3) af?',
        code: 'print(2 * 3)',
        options: const ['6', '23', '5'],
        correct: '23',
      ),
    );
    final fine = _stored(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: _prompt,
        code: 'print(1 + 1)',
        options: const [_right, _wrong],
        correct: _right,
      ),
    );
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'questions': [
          {
            ..._bankDoc(disputed, asked: 3, answered: 3),
            'optionFeedback': [
              {'option': '5', 'text': 'Nee.', 'quality': 'wrong'},
            ],
            'keyDisputedCount': 2,
            'keyDisputedAt': '2026-09-24T09:00:00.000Z',
          },
          _bankDoc(fine, asked: 2, answered: 2, correct: 2),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Questions'));
    await pumpUntilFound(tester, find.byType(QuestionsPage));
    await pumpUntilFound(tester, find.byKey(const Key('questions-tree')));
    await tester.tap(find.byKey(const Key('questions-subgoal-s1')));
    await pumpUntilFound(
      tester,
      find.byKey(Key('questions-card-${disputed.id}')),
    );
    await pumpUntilFound(tester, find.byKey(Key('questions-card-${fine.id}')));

    final warning = find.byKey(Key('questions-warning-${disputed.id}'));
    expect(warning, findsOneWidget);
    expect(
      tester.widget<Text>(warning).data,
      'The grading called the answer key wrong 2 times.',
    );
    // The card still shows the key the question was written with, for the
    // teacher to judge.
    final card = find.byKey(Key('questions-card-${disputed.id}'));
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(find.byKey(Key('questions-warning-${fine.id}')), findsNothing);

    // Hiding it is the teacher's call, as for any question.
    await tester.tap(find.byKey(Key('questions-hide-${disputed.id}')));
    await pumpUntilFound(
      tester,
      find.byKey(Key('questions-hidden-${disputed.id}')),
    );
    final stored = harness.cosmos['questions'][disputed.id]!;
    expect(stored['status'], 'hidden');
    expect(stored['keyDisputedCount'], 2, reason: 'kept on the write-back');

    await harness.dispose(tester);
  });

  testWidgets('without a `questions` container the teacher page says what to '
      'create instead of failing', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    harness.cosmos.route(
      'questions',
      UnprovisionedCosmos('questions').container,
    );

    await tester.tap(find.byTooltip('Questions'));
    await pumpUntilFound(tester, find.byType(QuestionsPage));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('questions-container-missing')),
    );
    expect(
      find.text('The question bank has not been set up yet'),
      findsOneWidget,
    );
    expect(find.textContaining('/subgoalId'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Created while the page is open: "Try again" loads the (empty) bank.
    harness.cosmos.route('questions', null);
    await tester.tap(find.byKey(const Key('questions-retry')));
    await pumpUntilFound(tester, find.byKey(const Key('questions-tree-empty')));

    await harness.dispose(tester);
  });
}
