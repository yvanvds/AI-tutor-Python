// End-to-end (#186): the conductor serves questions from the question bank.
//
// Once the bank holds enough questions that fit what the conductor plans —
// subgoal, target LO, type, level, language, active, and new to this
// student — it takes one from there instead of generating it (with the
// chance `QuestionBankShare`, above `QuestionBankMinimum` questions; both in
// `config/global`). A multiple-choice pick on a bank question is graded from
// its answer key: when the bank holds the feedback on that pick there is no
// model call at all; otherwise one call fetches the text, which the bank
// keeps for the next student. A code question from the bank is graded by the
// model like a fresh one, on its own exercise. And a missing bank changes
// nothing for the student: the question is generated. A grader on that
// feedback call that calls the key wrong (#198) — even while grading the
// pick as the key does — overrules the key like a contradicting grade.
//
// Real app, real navigation, real quiz and practice views, real tutor →
// question bank service → in-memory Cosmos; only the model is scripted, and
// an unscripted call fails on screen. The missing container goes through the
// real REST client (`UnprovisionedCosmos`, #170).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/question_bank_serving.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/bank_choice.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/unprovisioned_cosmos.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _key = '2';
const String _wrong = '11';
const String _storedText = 'Nee: 1 + 1 is een som, geen tekst.';
const String _fetchedText = 'Nee: de haakjes maken er geen tekst van.';

/// The seeded "Print" subgoal with a `predict` LO, so the conductor plans a
/// multiple-choice question for it (§1.1).
Map<String, dynamic> _printSubgoal({String kind = 'predict'}) => goalDoc(
  id: 's1',
  title: 'Print',
  parentId: 'r1',
  order: 1000,
  contentId: 's1',
  objectives: [
    {...objective('lo-print', 'Use print() to show text'), 'kind': kind},
  ],
);

/// `config/global` with the question bank's mix pinned: serve whenever
/// [minimum] new fitting questions are there.
Map<String, dynamic> _config({int minimum = 2}) => {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': '',
  'QuestionBankMinimum': minimum,
  'QuestionBankShare': 1.0,
};

/// A bank question on `s1` / `lo-print` / medium / `en`, as another
/// student's app stored it, last asked on [lastAskedAt].
Map<String, dynamic> _bankDoc(
  ChatResponse response, {
  required DateTime lastAskedAt,
  List<BankOptionFeedback> feedback = const [],
}) => {
  ...BankQuestion.fromResponse(
    response,
    subgoalId: 's1',
    rootGoalId: 'r1',
    targetLOIds: const ['lo-print'],
    difficulty: QuestionDifficulty.medium,
    language: 'en',
    model: 'gpt-5-mini',
    createdByUid: 'another-student',
    createdAt: DateTime.utc(2026, 9, 20),
  )!.toMap(),
  'askedCount': 3,
  'lastAskedAt': lastAskedAt.toIso8601String(),
  'optionFeedback': [for (final f in feedback) f.toJson()],
};

MultipleChoice _mcq(String prompt, String code) => MultipleChoice(
  type: 'multiple_choice',
  prompt: prompt,
  code: code,
  options: const [_key, _wrong, 'Error'],
  correct: _key,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The question least recently asked, and so the one served; and another.
  final served = _bankDoc(
    _mcq('Wat drukt print(1 + 1) af?', 'print(1 + 1)'),
    lastAskedAt: DateTime.utc(2026, 9, 21),
    feedback: const [
      BankOptionFeedback(
        option: _wrong,
        text: _storedText,
        quality: AnswerQuality.wrong,
      ),
    ],
  );
  final other = _bankDoc(
    _mcq('En print((1) + (1))?', 'print((1) + (1))'),
    lastAskedAt: DateTime.utc(2026, 9, 23),
  );

  /// Waits until the school's mix has reached the app — the update gate
  /// reads the config at sign-in and keeps polling it.
  Future<void> waitForMix(WidgetTester tester, AppHarness harness) => pumpUntil(
    tester,
    () =>
        harness.container
            .read(globalConfigServiceProvider)
            ?.questionBankShare ==
        1.0,
    reason: 'config/global never reached the app',
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

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      );

  List<Map<String, dynamic>> turns(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList();

  /// The picked option's row — the `AnimatedContainer` that draws its tint.
  Color optionHue(WidgetTester tester, String label) {
    final row = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final border = (row.decoration! as BoxDecoration).border! as Border;
    return border.top.color.withValues(alpha: 1);
  }

  testWidgets('a multiple-choice question comes from the bank, and a pick '
      'whose feedback the bank holds is graded on the spot from the key — '
      'no model call at all', (tester) async {
    // Any call fails loudly: nothing here may reach the model.
    final llm = ScriptedLlm(const []);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printSubgoal()],
        'config': [_config()],
        'questions': [served, other],
      },
    );
    await harness.boot(tester);
    await waitForMix(tester, harness);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(
      tester,
      find.textContaining('Wat drukt print(1 + 1) af?', findRichText: true),
    );
    await pumpUntilFound(tester, find.text(_wrong));
    await waitForIdle(tester, harness);
    expect(llm.sends, 0, reason: 'the question was not generated');

    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining('1 + 1 is een som', findRichText: true),
    );
    await waitForIdle(tester, harness);
    await tester.pump(AppDurations.hover);

    expect(llm.sends, 0, reason: 'the pick was graded without a call');
    expect(optionHue(tester, _wrong), AppColors.danger);
    expect(find.text('Next →'), findsOneWidget);
    expect(find.textContaining('went wrong'), findsNothing);

    // The turn record: the bank question, graded by its key — a moderate
    // negative on the target LO at the student's level (medium, x1.0).
    await pumpUntil(tester, () => turns(harness).length == 1);
    final turn = turns(harness).single;
    expect(turn['questionId'], served['id']);
    expect(turn['fromBank'], isTrue);
    expect(turn['gradedByKey'], isTrue);
    expect(turn['difficulty'], 'medium');
    expect(turn['overallQuality'], 'wrong');
    expect(turn['loSignals'], [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'moderate',
      },
    ]);
    expect(turn['appliedSignals'], [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'alphaDelta': 0.0,
        'betaDelta': 1.0,
      },
    ]);
    expect(turn.containsKey('usage'), isFalse, reason: 'no tokens spent');

    // The bank counted the ask and the answer; the stored text stayed.
    final bank = harness.cosmos['questions'];
    await pumpUntil(
      tester,
      () => bank[served['id'] as String]!['answeredCount'] == 1,
    );
    final doc = bank[served['id'] as String]!;
    expect(doc['askedCount'], 4);
    expect(doc['correctCount'], 0);
    expect(doc['optionFeedback'], hasLength(1));
    expect(bank[other['id'] as String]!['askedCount'], 3);

    await harness.dispose(tester);
  });

  testWidgets('a pick the bank has no feedback for costs one grading call, '
      'on the question\'s own exercise; the key decides and the text is '
      'kept for the next student', (tester) async {
    final llm = ScriptedLlm([
      llmEnvelope(
        text: _fetchedText,
        meta: jsonEncode({
          'type': 'mcq_feedback',
          'overallQuality': 'wrong',
          'loSignals': <Object>[],
          'followUp': {'question': 'En zonder haakjes?'},
        }),
      ),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printSubgoal()],
        'config': [_config(minimum: 1)],
        'questions': [other],
      },
    );
    await harness.boot(tester);
    await waitForMix(tester, harness);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
    await waitForIdle(tester, harness);
    expect(llm.sends, 0);

    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining('haakjes maken er geen tekst', findRichText: true),
    );
    await waitForIdle(tester, harness);

    expect(llm.sends, 1);
    expect(llm.sentScopes, [PreviousInputs.exercise]);
    final history = llm.sentHistories.single;
    expect(history, hasLength(1));
    expect(history.single['role'], 'assistant');
    expect(
      jsonDecode(history.single['content']!)['prompt'],
      'En print((1) + (1))?',
      reason: 'the grader reads the bank question as its exercise',
    );
    expect(jsonDecode(llm.sentInputs.single)['request_type'], 'mcq_answer');
    // The grader is told the key it is checked against, and how to treat
    // it (#197).
    expect(jsonDecode(llm.sentInputs.single)['correct_option'], _key);
    expect(llm.sentInstructions.single, contains('ANSWER KEY — STRICT.'));
    // No follow-up on a bank question.
    expect(
      find.textContaining('En zonder haakjes?', findRichText: true),
      findsNothing,
    );
    expect(
      harness.container.read(activeMcqProvider)?.feedbackQuality,
      AnswerQuality.wrong,
    );

    await pumpUntil(tester, () => turns(harness).length == 1);
    expect(turns(harness).single['gradedByKey'], isTrue);
    expect(turns(harness).single['fromBank'], isTrue);

    final bank = harness.cosmos['questions'];
    await pumpUntil(
      tester,
      () => (bank[other['id'] as String]!['optionFeedback'] as List).isNotEmpty,
      reason: 'the fetched text was not kept',
    );
    expect(bank[other['id'] as String]!['optionFeedback'], [
      {'option': _wrong, 'text': _fetchedText, 'quality': 'wrong'},
    ]);

    await harness.dispose(tester);
  });

  testWidgets('a grader that calls the key wrong (#198) — though it grades '
      'the pick as the key does — is a contradiction: its grade stands, '
      'and the bank stops serving the question', (tester) async {
    const text = 'Nee: print toont de som, niet de cijfers na elkaar.';
    final llm = ScriptedLlm([
      llmEnvelope(
        text: text,
        meta: jsonEncode({
          'type': 'mcq_feedback',
          'overallQuality': 'wrong',
          'loSignals': [
            {
              'subgoalId': 's1',
              'loId': 'lo-print',
              'signal': 'negative',
              'strength': 'strong',
            },
          ],
          'keyDisputed': true,
        }),
      ),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printSubgoal()],
        'config': [_config(minimum: 1)],
        'questions': [other],
      },
    );
    await harness.boot(tester);
    await waitForMix(tester, harness);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
    await waitForIdle(tester, harness);
    expect(llm.sends, 0, reason: 'served from the bank');

    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining('niet de cijfers na elkaar', findRichText: true),
    );
    await waitForIdle(tester, harness);
    await tester.pump(AppDurations.hover);

    // The student sees the grade and its text, as for any pick.
    expect(llm.sends, 1);
    expect(jsonDecode(llm.sentInputs.single)['correct_option'], _key);
    expect(optionHue(tester, _wrong), AppColors.danger);
    expect(find.textContaining('keyDisputed'), findsNothing);
    expect(
      harness.container.read(activeMcqProvider)?.feedback,
      text,
      reason: 'nothing added to the grader\'s text',
    );

    // The key did not decide: the grader's strong negative, not the key's
    // fixed moderate one.
    await pumpUntil(tester, () => turns(harness).length == 1);
    final turn = turns(harness).single;
    expect(turn['fromBank'], isTrue);
    expect(
      turn.containsKey('gradedByKey'),
      isFalse,
      reason: 'written only when the key decided',
    );
    expect(turn['overallQuality'], 'wrong');
    expect(turn['loSignals'], [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'strong',
      },
    ]);

    // The bank counts the dispute; the question is in doubt and is not
    // served again.
    final bank = harness.cosmos['questions'];
    await pumpUntil(
      tester,
      () => bank[other['id'] as String]!['keyDisputedCount'] == 1,
      reason: 'the dispute was not counted',
    );
    final stored = BankQuestion.tryFromCosmos(bank[other['id'] as String]!)!;
    expect(stored.optionFeedback.single.quality, AnswerQuality.wrong);
    expect(stored.graderDisagreesWithKey, isTrue);
    expect(BankChoice.servable(stored), isFalse);

    await harness.dispose(tester);
  });

  testWidgets('a complete-code question from the bank lands in the editor '
      'and is graded by the model on its own exercise', (tester) async {
    const code = 'print(1 + ___)';
    final llm = ScriptedLlm([
      codeFeedbackReply(
        text: 'Goed: 1 + 1 is 2.',
        quality: 'correct',
        loSignals: const [
          {
            'subgoalId': 's1',
            'loId': 'lo-print',
            'signal': 'positive',
            'strength': 'moderate',
          },
        ],
      ),
      // The grade asks for the next exercise; the bank has none left.
      completeCodeReply(text: 'Toon je naam.', code: 'naam = ___'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printSubgoal(kind: 'apply')],
        'config': [_config(minimum: 1)],
        'questions': [
          _bankDoc(
            CompleteCode(
              type: 'complete_code',
              prompt: 'Vul aan zodat 2 verschijnt.',
              code: code,
            ),
            lastAskedAt: DateTime.utc(2026, 9, 22),
          ),
        ],
      },
    );
    await harness.boot(tester);
    await waitForMix(tester, harness);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(PracticeView));
    String editorText() =>
        (tester.widget<CodeField>(find.byType(CodeField)).controller).text;
    await pumpUntil(
      tester,
      () =>
          find.byType(CodeField).evaluate().isNotEmpty && editorText() == code,
      reason: 'the bank question never reached the editor',
    );
    await waitForIdle(tester, harness);
    expect(llm.sends, 0);
    expect(
      find.textContaining('Vul aan zodat 2 verschijnt.', findRichText: true),
      findsWidgets,
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => editorText() == 'naam = ___',
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
    await waitForIdle(tester, harness);

    expect(llm.sentScopes, [
      PreviousInputs.exercise,
      PreviousInputs.newSession,
    ]);
    expect(jsonDecode(llm.sentInputs.first)['request_type'], 'submit_code');
    expect(
      jsonDecode(llm.sentHistories.first.single['content']!)['code'],
      code,
    );

    await pumpUntil(tester, () => turns(harness).length == 1);
    final turn = turns(harness).single;
    expect(turn['fromBank'], isTrue);
    expect(turn.containsKey('gradedByKey'), isFalse);
    expect(turn['overallQuality'], 'correct');

    await harness.dispose(tester);
  });

  testWidgets('without a `questions` container the question is generated '
      'as before, and nothing reaches the student', (tester) async {
    final llm = ScriptedLlm([
      llmEnvelope(
        text: 'Vers: wat drukt print(2) af?',
        meta: jsonEncode({
          'type': 'multiple_choice',
          'code': 'print(2)',
          'options': [
            {'option': '2'},
            {'option': 'Error'},
          ],
          'correct': 'A',
        }),
      ),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printSubgoal()],
        'config': [_config(minimum: 1)],
      },
    );
    await harness.boot(tester);
    final missing = UnprovisionedCosmos('questions');
    harness.cosmos.route('questions', missing.container);
    await waitForMix(tester, harness);

    await practise(tester);
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(
      tester,
      find.textContaining('Vers: wat drukt print(2) af?', findRichText: true),
    );
    await waitForIdle(tester, harness);

    expect(llm.sends, 1);
    expect(missing.requests, isNotEmpty, reason: 'the bank was asked');
    expect(missing.writes, isEmpty);
    expect(find.textContaining('went wrong'), findsNothing);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
