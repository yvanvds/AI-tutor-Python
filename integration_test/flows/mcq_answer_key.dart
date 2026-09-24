// End-to-end (#197): the grader of a multiple-choice pick is told the
// question's answer key, and the student is never shown it.
//
// The `mcQuestion` instructions ask the model to commit to an intended
// answer (`"correct": "B"`) "for the grader's downstream call", but the
// grading call never carried it. Now the grading call of a pick carries it as
// `correct_option` — the option's text, since the options are shuffled — and
// the system prompt of that call says how to treat it: the intended answer,
// which the grader still checks, so a wrong key is overruled and reported
// (the bank's `graderDisagreesWithKey`). The key stays out of everything the
// student sees: the quiz draws the key like any other option, before the
// pick and after the grade, and it is not on the exercise's history the
// question opens.
//
// Real app, real navigation, real quiz view, real TutorService → question
// formatter → instruction generator → connector history bookkeeping → question
// bank over the in-memory Cosmos. Only the model is scripted (`ScriptedLlm`,
// raw assistant text through the production parser), and what a flow asserts
// on is what the running app sent it and drew.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/mcq_answer_key.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// The line the answer-key directive opens with (`answerKeyDirective`).
const String _directive = 'ANSWER KEY — STRICT.';

/// A multiple-choice turn whose key is [letter], the positional letter the
/// `mcQuestion` instructions ask for.
String _mcqReply({
  required String prompt,
  required String code,
  required List<String> options,
  required String letter,
}) => llmEnvelope(
  text: prompt,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': code,
    'options': [
      for (final o in options) {'option': o},
    ],
    'correct': letter,
  }),
);

String _gradeReply({required String text, required String quality}) =>
    llmEnvelope(
      text: text,
      meta: jsonEncode({
        'type': 'mcq_feedback',
        'overallQuality': quality,
        'loSignals': <Object>[],
      }),
    );

/// The option row for [label] — the `AnimatedContainer` that draws it.
BoxDecoration _row(WidgetTester tester, String label) =>
    tester
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

Color _border(BoxDecoration d) => (d.border! as Border).top.color;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Leerpad → theory → "Try it yourself": the exercise request plays the
  /// scripted multiple-choice turn and opens the quiz.
  Future<void> openQuiz(WidgetTester tester, String anOption) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(anOption));
  }

  /// Waits until the tutor is idle, then past the option rows' tint
  /// animation, so what is asserted is what the student sees.
  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) async {
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    await tester.pump(AppDurations.hover);
    await tester.pump();
  }

  /// Picks [option] and waits until the grade containing [feedback] is on
  /// screen, the tutor is idle again and the option tints have settled.
  Future<void> pickAndWait(
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

  Map<String, dynamic> sent(ScriptedLlm llm, int i) =>
      jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;

  testWidgets('the grader of a pick is told the key as option text; the quiz '
      'draws the key like any other option, before the pick and after the '
      'grade', (tester) async {
    const prompt = 'Wat drukt print(len("abc")) af?';
    const key = '3';
    const picked = 'abc';
    const other = 'Error';
    const feedback = 'Nee: len telt de tekens, het toont ze niet.';
    final llm = ScriptedLlm([
      _mcqReply(
        prompt: prompt,
        code: 'print(len("abc"))',
        options: const [picked, key, other],
        letter: 'B',
      ),
      _gradeReply(text: feedback, quality: 'wrong'),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    await openQuiz(tester, key);
    await waitForIdle(tester, harness);

    // Before the pick the key is drawn like the others, and only the
    // question was asked for.
    for (final label in const [key, picked, other]) {
      expect(_border(_row(tester, label)), AppColors.ink2, reason: label);
    }
    expect(llm.sends, 1);

    await pickAndWait(tester, harness, picked, feedback);
    expect(llm.remaining, 0);

    // After a wrong pick and its grade: the pick is red, and the key is not
    // singled out — it looks exactly like the other option not picked.
    expect(
      _border(_row(tester, picked)).withValues(alpha: 1),
      AppColors.danger,
    );
    expect(_border(_row(tester, key)), AppColors.ink2);
    expect(_row(tester, key).color, _row(tester, other).color);
    expect(_border(_row(tester, key)), _border(_row(tester, other)));
    expect(find.textContaining('correct_option'), findsNothing);
    expect(
      harness.container.read(activeMcqProvider)?.feedback,
      feedback,
      reason: 'the student sees the grader\'s text, nothing added to it',
    );

    // The generation call knew nothing of a key yet; the grading call of the
    // pick is told it, by content — the letter was B, the options shuffled.
    expect(llm.sentScopes, [
      PreviousInputs.newSession,
      PreviousInputs.exercise,
    ]);
    expect(sent(llm, 0).containsKey('correct_option'), isFalse);
    expect(llm.sentInstructions[0], isNot(contains(_directive)));
    final grading = sent(llm, 1);
    expect(grading['request_type'], 'mcq_answer');
    expect(grading['answer'], picked);
    expect(grading['correct_option'], key);
    // …with the rule for it in the system prompt, above the language
    // directive that has to stay last.
    final system = llm.sentInstructions[1];
    expect(system, contains(_directive));
    expect(system, contains('never adjust it to agree with the key'));
    expect(
      system.indexOf(_directive),
      lessThan(system.indexOf('OUTPUT LANGUAGE')),
    );
    // The exercise the grader reads: the question as the student saw it,
    // without the key.
    final history = llm.sentHistories[1];
    expect(history, hasLength(1));
    final question = jsonDecode(history.single['content']!) as Map;
    expect(question['prompt'], prompt);
    expect(question.containsKey('correct'), isFalse);

    await harness.dispose(tester);
  });

  testWidgets('a grader that sees the key can still overrule a wrong one: '
      'its grade is what the student gets, and the bank flags the '
      'question', (tester) async {
    const truth = '6';
    const wrongKey = '23';
    const feedback = 'Juist: 2 * 3 is een vermenigvuldiging, dat geeft 6.';
    final llm = ScriptedLlm([
      // The model's key is off: `2 * 3` prints 6, not 23.
      _mcqReply(
        prompt: 'Wat drukt print(2 * 3) af?',
        code: 'print(2 * 3)',
        options: const [truth, wrongKey, 'Error'],
        letter: 'B',
      ),
      _gradeReply(text: feedback, quality: 'correct'),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);
    final bank = harness.cosmos['questions'];

    await openQuiz(tester, truth);
    await waitForIdle(tester, harness);
    await pickAndWait(tester, harness, truth, 'dat geeft 6');

    // The grader was told the (wrong) key and judged the pick right anyway:
    // that is what the student sees.
    expect(sent(llm, 1)['correct_option'], wrongKey);
    expect(_border(_row(tester, truth)).withValues(alpha: 1), AppColors.accent);
    expect(_border(_row(tester, wrongKey)), AppColors.ink2);

    // The turn is graded as the grader said, and the bank keeps the verdict
    // against the key — the warning on the teacher's Questions page, and the
    // reason the bank never serves the question (CONDUCTOR_POLICY §2.7).
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.isNotEmpty,
      reason: 'the grade was not recorded',
    );
    expect(
      harness.cosmos['turn_history'].docs.values.single['overallQuality'],
      'correct',
    );
    await pumpUntil(
      tester,
      () =>
          bank.docs.isNotEmpty &&
          (bank.docs.values.single['optionFeedback'] as List).isNotEmpty,
      reason: 'the grade was not counted on the bank question',
    );
    final stored = BankQuestion.tryFromCosmos(bank.docs.values.single)!;
    expect(stored.correctOption, wrongKey);
    expect(stored.graderDisagreesWithKey, isTrue);

    await harness.dispose(tester);
  });
}
