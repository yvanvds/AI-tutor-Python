// End-to-end (#185): the question bank.
//
// Every question the tutor generated used to be thrown away once asked;
// only the turn record remained. Now each one is stored in the `questions`
// container — deduplicated on its content, with what it was asked for —
// and the graded answer to it is counted there, a multiple-choice pick with
// the feedback the student got on it. The turn record names the question.
// The teacher gets a Questions page to weed the bank out: per subgoal, each
// question as the student saw it, how often it was asked and how often
// answered right, sorted on that share, with hide and a note.
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

String _gradeReply() => llmEnvelope(
  text: _feedback,
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'wrong',
    'loSignals': <Object>[],
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
  /// scripted multiple-choice turn and opens the quiz.
  Future<void> openQuiz(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
  }

  /// The wrong pick, its feedback, then "Next" to the complete-code turn.
  Future<void> answerAndMoveOn(WidgetTester tester, AppHarness harness) async {
    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining('1 + 1 is een som', findRichText: true),
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
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

  testWidgets('a generated question lands in the bank with what it was asked '
      'for, and the pick on it is counted with the feedback the student got', (
    tester,
  ) async {
    final llm = ScriptedLlm([
      _mcqReply(),
      _gradeReply(),
      completeCodeReply(text: 'Geef naam een waarde.', code: _next),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    final bank = harness.cosmos['questions'];

    await openQuiz(tester);
    await answerAndMoveOn(tester, harness);
    await pumpUntil(
      tester,
      () => bank.docs.length == 2,
      reason: 'the next exercise was not stored',
    );

    final mcq = bank.docs.values.firstWhere(
      (d) => d['questionType'] == 'mcQuestion',
    );
    expect(mcq['id'], startsWith('s1_'));
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
      'prompt': _prompt,
      'code': 'print(1 + 1)',
      'options': [
        {'option': _right},
        {'option': _wrong},
        {'option': 'Error'},
      ],
      'correct': _right,
    });
    expect(mcq['askedCount'], 1);
    expect(mcq['answeredCount'], 1);
    expect(mcq['correctCount'], 0);
    expect(mcq['optionFeedback'], [
      {'option': _wrong, 'text': _feedback, 'quality': 'wrong'},
    ]);

    // The turn record names the question it graded.
    final turns = harness.cosmos['turn_history'].docs.values.toList();
    expect(turns, hasLength(1));
    expect(turns.single['questionId'], mcq['id']);

    final next = bank.docs.values.firstWhere(
      (d) => d['questionType'] == 'completeCodeQuestion',
    );
    expect(next['payload']['code'], _next);
    expect(next['answeredCount'], 0);

    await harness.dispose(tester);
  });

  testWidgets('without a `questions` container the student practises as '
      'before, and nothing is stored', (tester) async {
    final llm = ScriptedLlm([
      _mcqReply(),
      _gradeReply(),
      completeCodeReply(text: 'Geef naam een waarde.', code: _next),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    // The live account before the teacher creates it: every other container
    // exists, `questions` does not.
    final missing = UnprovisionedCosmos('questions');
    harness.cosmos.route('questions', missing.container);

    await openQuiz(tester);
    await answerAndMoveOn(tester, harness);
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

  testWidgets('the teacher reviews the bank: a count per subgoal, each '
      'question as the student saw it, sorted on the share correct, hidden '
      'and noted', (tester) async {
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
          _bankDoc(other),
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
    expect(subtitle('s1'), '2 questions · 2 new');
    expect(subtitle('s2'), '1 question · 1 new');

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

    // Hide the one that is too hard to be fair.
    await tester.tap(find.byKey(Key('questions-hide-${hard.id}')));
    await pumpUntilFound(
      tester,
      find.byKey(Key('questions-hidden-${hard.id}')),
    );
    final stored = harness.cosmos['questions'][hard.id]!;
    expect(stored['status'], 'hidden');
    expect(stored['reviewedAt'], isA<String>());
    expect(harness.cosmos['questions'].docs, hasLength(3));
    await pumpUntil(tester, () => subtitle('s1') == '2 questions · 1 new');

    // A note on the easy one.
    await tester.tap(find.byKey(Key('questions-note-${easy.id}')));
    await pumpUntilFound(tester, find.byKey(const Key('questions-note-field')));
    await tester.enterText(
      find.byKey(const Key('questions-note-field')),
      'Te makkelijk voor medium.',
    );
    await tester.tap(find.byKey(const Key('questions-note-save')));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    await pumpUntilFound(
      tester,
      find.byKey(Key('questions-note-text-${easy.id}')),
    );
    expect(
      harness.cosmos['questions'][easy.id]!['teacherNote'],
      'Te makkelijk voor medium.',
    );

    // Both are reviewed now: the filter leaves nothing of this subgoal.
    await tester.tap(find.byKey(const Key('questions-filter-unreviewed')));
    await pumpUntilFound(tester, find.byKey(const Key('questions-list-empty')));
    expect(find.byKey(Key('questions-card-${hard.id}')), findsNothing);
    expect(subtitle('s1'), '2 questions');

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
