// End-to-end (#217): every oefening is worth XP, right or wrong, so the level
// in the top bar moves during a lesson even when no learning objective
// reaches mastery.
//
// Before, XP was mastery alone: a lesson spent on one hard LO showed nothing,
// and the bar ran backwards when an LO fell under the bar again. Now the
// account doc carries `oefeningCount` — one per question at its first graded
// answer, never for a follow-up — and every oefening is worth
// `kXpPerOefening` on top of the mastery XP. A level reached that way gets
// its own moment: "Level N" and how many oefeningen the student has made.
//
// Why this has to run against the real app: the count is written by the
// conductor in the same account write as the calibration, reaches the pill
// only through the account doc's 5 s poll and three providers, and the
// level-up moment is armed by the tutor before the write and fired by a
// listener `TutorService` sets up at boot. A follow-up is told apart by the
// tutor's own follow-up bookkeeping. Nothing below the running app has that
// chain. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/oefening_xp.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _right = '2';
const String _printExercise = 'print(___)';
const String _wrong = '11';

String _mcqReply(String prompt) => llmEnvelope(
  text: prompt,
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

String _mcqGrade(String text) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'wrong',
    'loSignals': [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'moderate',
      },
    ],
  }),
);

/// The student's account with [count] oefeningen already made.
Map<String, List<Map<String, dynamic>>> _made(int count) => {
  'accounts': [
    {...accountDoc(studentIdentity), 'oefeningCount': count},
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> xpPillReads(WidgetTester tester, String text) => pumpUntil(
    tester,
    () => find.text(text).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
    reason: 'the XP pill never read "$text"',
  );

  /// Text inside the celebration itself — the top bar has a "Level N" of
  /// its own.
  Finder inOverlay(String text) => find.descendant(
    of: find.byType(LevelUpOverlay),
    matching: find.text(text),
  );

  /// The `oefeningCount` on the student's account doc.
  int? storedCount(AppHarness harness) =>
      harness.cosmos['accounts'].docs[kStudentUid]?['oefeningCount'] as int?;

  /// Leerpad → theory → "Try it yourself": the scripted multiple-choice turn
  /// opens the quiz.
  Future<void> openQuiz(WidgetTester tester, AppHarness harness) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_wrong));
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
  }

  Future<void> pickWrong(WidgetTester tester, String feedback) async {
    await tester.tap(find.text(_wrong));
    await pumpUntilFound(
      tester,
      find.textContaining(feedback, findRichText: true),
    );
  }

  testWidgets('a wrong answer is still an oefening: the bar moves 20 XP, and '
      'the one that tips it over a level is celebrated with the count', (
    tester,
  ) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
        _mcqReply('Wat drukt print(1 + 1) af?'),
        _mcqGrade('Nee: 1 + 1 is een som.'),
      ]),
      extraDocs: _made(24),
    );
    await harness.boot(tester);

    // 24 oefeningen, nothing mastered: 480 of the 500 XP of level 1.
    await xpPillReads(tester, '480 / 500');
    expect(kXpPerOefening, 20);

    await openQuiz(tester, harness);
    await pickWrong(tester, '1 + 1 is een som');

    // The 25th oefening is on the account doc…
    await pumpUntil(
      tester,
      () => storedCount(harness) == 25,
      reason: 'the wrong answer was not counted as an oefening',
    );

    // …and on the next account poll it is level 2, with the moment that
    // says how many oefeningen got there — not a mastered concept.
    await pumpUntil(
      tester,
      () => inOverlay('Level 2').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'crossing into level 2 by an oefening opened no level-up',
    );
    expect(inOverlay("You've done 25 exercises so far."), findsOneWidget);
    expect(inOverlay('+20 XP · EXERCISE DONE'), findsOneWidget);
    expect(find.textContaining("You've mastered"), findsNothing);
    expect(find.text('0 / 500'), findsWidgets);

    await tester.tap(inOverlay('Keep learning'));
    await pumpUntilGone(tester, inOverlay('Level 2'));

    await harness.dispose(tester);
  });

  testWidgets('a follow-up is the same oefening continued: answering it '
      'adds no XP', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Toon de tekst Hallo.', code: _printExercise),
        llmEnvelope(
          text: 'Bijna: er staat nog een open plek.',
          meta: jsonEncode({
            'type': 'code_feedback',
            'suggestion': '',
            'overallQuality': 'wrong',
            'loSignals': [
              {
                'subgoalId': 's1',
                'loId': 'lo-print',
                'signal': 'negative',
                'strength': 'moderate',
              },
            ],
            'followUp': {'question': 'Wat zet je tussen de haakjes?'},
          }),
        ),
        llmEnvelope(
          text: 'Juist, de tekst tussen aanhalingstekens.',
          meta: jsonEncode({
            'type': 'socratic_feedback',
            'overallQuality': 'correct',
            'loSignals': <Object>[],
          }),
        ),
        // The follow-up's grade asks for the next exercise.
        completeCodeReply(text: 'Nog een.', code: 'print(___ + 1)'),
      ]),
      // "Print" without its lesson, so the leerpad opens the editor.
      extraDocs: {
        'goals': [
          goalDoc(
            id: 's1',
            title: 'Print',
            parentId: 'r1',
            order: 1000,
            objectives: [objective('lo-print', 'Use print() to show text')],
          ),
        ],
      },
    );
    await harness.boot(tester);
    await xpPillReads(tester, '0 / 500');

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          tester.widget<CodeField>(find.byType(CodeField)).controller.text ==
          _printExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => storedCount(harness) == 1,
      timeout: const Duration(seconds: 30),
      reason: 'the first answer was not counted',
    );

    // The follow-up comes in the chat; the student answers it there.
    await pumpUntilFound(
      tester,
      find.textContaining('Wat zet je tussen', findRichText: true),
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    final composer = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, composer);
    await tester.tap(composer);
    await tester.pump();
    await tester.enterText(composer, 'De tekst "Hallo".');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    // Graded as a follow-up, and recorded as one…
    List<Map<String, dynamic>> turns() =>
        harness.cosmos['turn_history'].docs.values.toList();
    await pumpUntil(
      tester,
      () => turns().any((t) => t['isFollowUp'] == true),
      timeout: const Duration(seconds: 30),
      reason: 'the follow-up answer was never graded',
    );
    expect(turns(), hasLength(2));
    // …but not counted: the account write for it came before its turn
    // record, and the count is still 1.
    expect(storedCount(harness), 1);
    await xpPillReads(tester, '20 / 500');
    // A poll later the pill still says one oefening.
    final settle = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(settle)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('20 / 500'), findsWidgets);
    expect(find.text('40 / 500'), findsNothing);
    expect(storedCount(harness), 1);

    await harness.dispose(tester);
  });
}
