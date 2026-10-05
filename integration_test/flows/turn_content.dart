// End-to-end (#228): what a student saw, answered and was told on an
// oefening is kept until the end of the school year — and the student is
// told so in Options.
//
// `turn_history` says *that* an oefening went wrong; the `turn_content` doc
// next to it, with the same id, says *why*: the question as it was on
// screen, the answer handed in, the feedback, the grader's own signals
// before the scope check and why each dropped one did not count, where the
// student was and how the session began, and the hints asked. It carries a
// `ttl` that runs out on the day `config/global` names (1 July unless the
// school set another), at midnight Belgian time.
//
// And it is best-effort, like the question bank: without the container the
// student practises as before.
//
// #232 — a progress reset takes it along: "Reset all progress" deletes the
// content of every oefening with its turn record, and resetting one subgoal
// the content on that subgoal — and the dialog says so, in the student's
// language. The question bank stays exactly as it was, also the questions
// this student was the first to get: it is kept for next year.
//
// Real app, real navigation (learning path → theory → practice), real
// practice view, editor and hint button, real TutorService → grader payload
// → scope check → conductor → turn content service → in-memory Cosmos. Only
// the model is scripted. The missing container goes through the real REST
// client (`UnprovisionedCosmos`, #170).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/turn_content.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/keep_until.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/in_memory_cosmos.dart';
import '../../test/helpers/unprovisioned_cosmos.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exercise = 'print(___)';
const String _answer = 'print(Hallo)';
const String _next = 'naam = ___';
const String _hint = 'Tekst staat tussen aanhalingstekens.';
const String _feedback = 'Bijna: zonder aanhalingstekens is Hallo een naam.';

/// The grader's signals: on the asked LO, on a later subgoal of the goal
/// (a forward reference) and on a subgoal outside the goal.
const List<Map<String, String>> _graderSignals = [
  {
    'subgoalId': 's1',
    'loId': 'lo-print',
    'signal': 'negative',
    'strength': 'moderate',
  },
  {
    'subgoalId': 's2',
    'loId': 'lo-var',
    'signal': 'negative',
    'strength': 'weak',
  },
  {
    'subgoalId': 'elders',
    'loId': 'lo-x',
    'signal': 'positive',
    'strength': 'weak',
  },
];

/// The exercise, a hint, its grade, and the exercise after it.
List<String> _script() => [
  completeCodeReply(text: 'Toon het woord Hallo.', code: _exercise),
  llmEnvelope(text: _hint, meta: '{"type":"hint"}'),
  codeFeedbackReply(
    text: _feedback,
    quality: 'partial',
    loSignals: _graderSignals,
  ),
  completeCodeReply(text: 'Geef naam een waarde.', code: _next),
];

/// `config/global` with the day the school keeps the content until.
Map<String, dynamic> _config(String keepUntil) => {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': '',
  'TurnContentKeepUntil': keepUntil,
};

/// A bank question on "Print" about what `print(a + b)` shows, the first
/// time asked to [createdByUid], and counted since.
Map<String, dynamic> _bankDoc(int a, int b, {required String createdByUid}) => {
  ...BankQuestion.fromResponse(
    MultipleChoice(
      type: 'multiple_choice',
      prompt: 'Wat drukt dit af?',
      code: 'print($a + $b)',
      options: ['$a$b', '${a + b}', 'Error'],
      correct: '${a + b}',
    ),
    subgoalId: 's1',
    rootGoalId: 'r1',
    targetLOIds: const ['lo-print'],
    difficulty: QuestionDifficulty.medium,
    language: 'en',
    model: 'gpt-5-mini',
    createdByUid: createdByUid,
    createdAt: DateTime.utc(2026, 9, 20),
  )!.toMap(),
  'askedCount': 4,
  'answeredCount': 3,
  'correctCount': 2,
  'lastAskedAt': '2026-09-29T10:00:00.000Z',
};

/// The question bank: one question this student was the first to get, one
/// another student was.
List<Map<String, dynamic>> _bank() => [
  _bankDoc(1, 1, createdByUid: kStudentUid),
  _bankDoc(2, 2, createdByUid: 'another-student'),
];

typedef _BankSnapshot = ({
  Map<String, dynamic> docs,
  Map<String, String?> etags,
});

/// The bank as it stands, docs and `_etag`s: a write that left a doc as it
/// was still gives it a new `_etag`.
_BankSnapshot _snapshot(InMemoryCosmos bank) => (
  docs: jsonDecode(jsonEncode(bank.docs)) as Map<String, dynamic>,
  etags: {for (final id in bank.docs.keys) id: bank.etagOf(id)},
);

/// Not a bank question deleted, changed or even written again.
void _expectUntouched(InMemoryCosmos bank, _BankSnapshot before) {
  expect(bank.docs, hasLength(2));
  expect(bank.docs, equals(before.docs));
  expect(
    {for (final id in bank.docs.keys) id: bank.etagOf(id)},
    before.etags,
    reason: 'a bank question was written',
  );
  expect(
    bank.docs.values.where((d) => d['createdByUid'] == kStudentUid),
    hasLength(1),
  );
}

/// Brings [finder] on the Options page into view and taps it.
Future<void> _tapInOptions(WidgetTester tester, Finder finder) async {
  final scrollable = optionsScrollable();
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Future<void> waitForEditor(WidgetTester tester, String code) => pumpUntil(
    tester,
    () =>
        find.byType(CodeField).evaluate().isNotEmpty &&
        editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise never reached the editor',
  );

  /// Learning path → "Continue" → the theory → "Try it yourself": the
  /// exercise request plays the scripted complete-code turn.
  Future<void> openExercise(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForEditor(tester, _exercise);
  }

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
        timeout: const Duration(seconds: 30),
        reason: 'the tutor never went idle',
      );

  /// Asks a hint, types [_answer] in the editor, hands it in and waits for
  /// the next exercise.
  Future<void> hintAnswerAndGoOn(
    WidgetTester tester,
    AppHarness harness,
  ) async {
    await tester.tap(find.byTooltip('Ask for a hint'));
    await pumpUntilFound(
      tester,
      find.textContaining('aanhalingstekens.', findRichText: true),
    );
    await waitForIdle(tester, harness);

    harness.container
            .read(codeServiceProvider(SessionMode.practice))
            .controller
            .text =
        _answer;
    await tester.pump();
    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntilFound(
      tester,
      find.textContaining('zonder aanhalingstekens', findRichText: true),
    );
    await waitForEditor(tester, _next);
    await waitForIdle(tester, harness);
  }

  testWidgets('an oefening leaves its content next to its turn record: the '
      'question on screen, the code handed in, the feedback, the grader\'s '
      'signals and why the dropped ones did not count, where the student '
      'was and how the session began, the hint — kept until the school\'s '
      'day', (tester) async {
    final llm = ScriptedLlm(_script());
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'config': [_config('06-30')],
      },
    );
    await harness.boot(tester);

    await openExercise(tester);
    await hintAnswerAndGoOn(tester, harness);
    expect(llm.remaining, 0);

    final turns = harness.cosmos['turn_history'].docs.values.toList();
    expect(turns, hasLength(1));
    final turn = turns.single;
    final contents = harness.cosmos['turn_content'];
    await pumpUntil(
      tester,
      () => contents.docs.isNotEmpty,
      reason: 'no content was written for the oefening',
    );
    expect(contents.docs.keys, [turn['id']]);
    final doc = contents.docs.values.single;

    expect(doc['uid'], kStudentUid);
    expect(doc['turnAt'], turn['turnAt']);
    expect(doc['subgoalId'], 's1');
    expect(doc['questionType'], 'completeCodeQuestion');
    expect(doc['isFollowUp'], isFalse);
    expect(doc['question'], {
      'text': 'Toon het woord Hallo.',
      'code': _exercise,
      'questionId': turn['questionId'],
    });
    expect(doc['answer'], {'code': _answer});
    expect(doc['feedback'], _feedback);
    expect(doc['rawSignals'], _graderSignals);
    // The one on the asked LO counted; the others did not, and say why —
    // the scope check's drop first, then the conductor's. The turn record
    // has only what passed the scope check, the forward reference included.
    expect(turn['loSignals'], [_graderSignals[0], _graderSignals[1]]);
    expect((turn['appliedSignals'] as List).cast<Map>().map((a) => a['loId']), [
      'lo-print',
    ]);
    expect(doc['droppedSignals'], [
      {..._graderSignals[2], 'reason': 'outOfScope'},
      {..._graderSignals[1], 'reason': 'laterSubgoal'},
    ]);
    expect(doc['context'], {
      'activeRootId': 'r1',
      'activeSubgoalId': 's1',
      'selectedRootId': 'r1',
      'selectedChildId': 's1',
      'preferredRootId': 'r1',
      'preferredChildId': null,
      'sessionStart': 'continueLearningPath',
    });
    expect(doc['hintCount'], 1);

    // Kept until 30 June, the day in config/global, at midnight Brussels
    // time; Cosmos counts the ttl down from the write.
    final turnAt = DateTime.parse(turn['turnAt'] as String);
    final until = const KeepUntil(6, 30).after(turnAt);
    expect(doc['keepUntil'], until.toIso8601String());
    final ttl = doc['ttl'] as int;
    final expected = until.difference(DateTime.now().toUtc()).inSeconds;
    expect(ttl, inInclusiveRange(expected - 5, expected + 60));

    await harness.dispose(tester);
  });

  testWidgets('without a `turn_content` container the student practises as '
      'before, and nothing is stored', (tester) async {
    final llm = ScriptedLlm(_script());
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    final missing = UnprovisionedCosmos('turn_content');
    harness.cosmos.route('turn_content', missing.container);

    await openExercise(tester);
    await hintAnswerAndGoOn(tester, harness);
    expect(llm.remaining, 0);

    expect(find.textContaining('went wrong'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(harness.cosmos['turn_history'].docs, hasLength(1));
    await pumpUntil(
      tester,
      () => missing.requests.isNotEmpty,
      reason: 'the content was never even tried',
    );
    expect(harness.cosmos['turn_content'].docs, isEmpty);

    await harness.dispose(tester);
  });

  testWidgets('Options tells the student their questions and answers are '
      'kept until the end of the school year — in their language', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    Future<void> seeSentence(String text) async {
      final sentence = find.text(text);
      final scrollable = optionsScrollable();
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(sentence, 120, scrollable: scrollable);
      await tester.ensureVisible(sentence);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sentence, findsOneWidget);
      expect(tester.getRect(sentence).height, greaterThan(0));
    }

    await seeSentence(
      'Your questions and answers are kept until the end of the school '
      'year, so your teacher can see where you get stuck.',
    );
    expect(find.text('Your answers'), findsOneWidget);

    tester.state<ScrollableState>(optionsScrollable()).position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));

    await seeSentence(
      'Je vragen en antwoorden worden bewaard tot het einde van het '
      'schooljaar, zodat je leerkracht kan zien waar het vastloopt.',
    );
    expect(find.text('Je antwoorden'), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets('Reset all progress takes the content of the oefeningen along '
      'with their turn records, says so, and leaves the question bank as it '
      'was', (tester) async {
    final llm = ScriptedLlm(_script());
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'config': [_config('06-30')],
        'questions': _bank(),
      },
    );
    await harness.boot(tester);

    await openExercise(tester);
    await hintAnswerAndGoOn(tester, harness);
    expect(llm.remaining, 0);

    final contents = harness.cosmos['turn_content'];
    final turns = harness.cosmos['turn_history'];
    await pumpUntil(
      tester,
      () => contents.docs.isNotEmpty,
      reason: 'no content was written for the oefening',
    );
    expect(contents.docs.keys, turns.docs.keys);
    final bank = harness.cosmos['questions'];
    final before = _snapshot(bank);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await _tapInOptions(tester, find.text('Reset all progress'));
    await pumpUntilFound(tester, find.text('Reset all progress?'));
    expect(
      find.text(
        'This deletes all your progress, learning history, tutor beliefs, '
        'questions and answers, and resets the difficulty calibration to '
        'medium. This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset everything'));
    await pumpUntilFound(tester, find.text('All progress has been reset.'));

    expect(contents.docs, isEmpty);
    expect(turns.docs, isEmpty);
    _expectUntouched(bank, before);

    await harness.dispose(tester);
  });

  testWidgets('resetting one subgoal takes the content of the oefeningen on '
      'it along, says so in Dutch, and leaves the rest and the question bank '
      'as they were', (tester) async {
    Map<String, dynamic> content(String id, String uid, String subgoalId) => {
      'id': id,
      'uid': uid,
      'type': 'turn_content',
      'turnAt': '2026-10-01T09:00:00.000Z',
      'subgoalId': subgoalId,
      'feedback': 'Bijna.',
    };
    final harness = AppHarness(
      extraDocs: {
        'turn_content': [
          content('t1', kStudentUid, 's1'),
          content('t2', kStudentUid, 's1'),
          content('t3', kStudentUid, 's2'),
          content('t4', 'another-student', 's1'),
        ],
        'questions': _bank(),
      },
    );
    await harness.boot(tester);
    final contents = harness.cosmos['turn_content'];
    final bank = harness.cosmos['questions'];
    final before = _snapshot(bank);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    tester.state<ScrollableState>(optionsScrollable()).position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));

    await _tapInOptions(tester, find.text('Eén doel wissen…'));
    await pumpUntilFound(tester, find.text('Voortgang van een doel wissen'));
    final printRow = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Print'),
    );
    await pumpUntilFound(tester, printRow);
    await tester.tap(printRow);
    await pumpUntilFound(tester, find.text('"Print" wissen?'));
    expect(
      find.text(
        'Je voortgang, leergeschiedenis, tutorinschattingen, vragen en '
        'antwoorden voor dit subdoel worden verwijderd. Dit kan niet '
        'ongedaan gemaakt worden.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Wissen'));
    await pumpUntilFound(tester, find.text('Voortgang van "Print" is gewist.'));

    expect(contents.docs.keys, ['t3', 't4']);
    _expectUntouched(bank, before);

    await harness.dispose(tester);
  });
}
