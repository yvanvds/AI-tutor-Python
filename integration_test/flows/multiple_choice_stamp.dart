// End-to-end (#279, formula 1.1): a right pick weighs half, and two right
// multiple-choice questions are no achieved goal. The stamp wants two own
// questions answered right, one of them no multiple choice (CONDUCTOR_POLICY
// §4.1, condition 4) — so once a right pick is on record without its
// non-pick, the conductor asks that LO another type: `socraticQuestion` for
// a `recall` LO (§2.2).
//
// The teacher saw stamps fall on two clicks: of the 201 stamps since 21
// October, 83 rested as own questions on multiple choice alone, and a pick
// weighed as much as a program the student wrote — the grader gave
// `strong` on 437 of 440 right picks. Here "Print" has two `recall` LOs. A
// right pick on `lo-print` adds half the weight of a right answer; a fresh
// `lo-quote` still starts with a pick, the gentle way in; and the next
// question on `lo-print` is a question in the chat, not a quiz. Answered
// right, it counts as the right non-pick, but the belief is not over the
// bar yet, so no stamp. A second test seeds `lo-print` over the bar on four
// right picks — the stamp of before — and shows that it is not mastered: the
// session asks it a socratic question, whose right answer stamps it, and
// "Print" is reached.
//
// Real app, real navigation, real practice and quiz views, real chat
// composer, real TutorService → conductor → belief math → Cosmos services.
// Only the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/multiple_choice_stamp.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kPrintKey = 'Het toont tekst op het scherm';
const String kPrintWrong = 'Het slaat tekst op';
const String kQuoteKey = 'Zodat Python weet dat het tekst is';
const String kQuoteWrong = 'Zodat het mooier staat';
const String kOpenQuestion = 'Leg in je eigen woorden uit wat print() doet.';
const String kNextSubgoal = 'stad = ___\nprint(stad)';

Map<String, String> _signal(String loId, String kind) => {
  'subgoalId': 's1',
  'loId': loId,
  'signal': kind,
  'strength': 'strong',
};

/// A multiple-choice turn whose key is option [letter].
String _mcqReply(String prompt, List<String> options, String letter) =>
    llmEnvelope(
      text: prompt,
      meta: jsonEncode({
        'type': 'multiple_choice',
        'code': '',
        'options': [
          for (final o in options) {'option': o},
        ],
        'correct': letter,
      }),
    );

/// The grade of a pick: [quality], with a strong signal of [kind] on [loId].
String _mcqGrade(String text, String quality, String loId, String kind) =>
    llmEnvelope(
      text: text,
      meta: jsonEncode({
        'type': 'mcq_feedback',
        'overallQuality': quality,
        'loSignals': [_signal(loId, kind)],
      }),
    );

String _openQuestion(String prompt) => llmEnvelope(
  text: prompt,
  meta: jsonEncode({'type': 'socratic_question', 'prompt': prompt}),
);

/// A right answer to the open question on [loId].
String _openRight(String text, String loId) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'socratic_feedback',
    'overallQuality': 'correct',
    'loSignals': [_signal(loId, 'positive')],
  }),
);

/// "Print" without its lesson, so the leerpad opens the practice view, with
/// `recall` LOs: [ids] of [_statements].
Map<String, dynamic> _print(List<String> ids) => goalDoc(
  id: 's1',
  title: 'Print',
  parentId: 'r1',
  order: 1000,
  objectives: [
    for (final id in ids)
      {...objective(id, _statements[id]!), 'kind': 'recall'},
  ],
);

const Map<String, String> _statements = {
  'lo-print': 'Say what print() does',
  'lo-quote': 'Say why text needs quotes',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
        timeout: const Duration(seconds: 30),
        reason: 'the tutor never went idle',
      );

  Future<void> openPractice(WidgetTester tester, AppHarness harness) async {
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
  }

  /// The quiz with [option] on it, the student picks it, and the grade
  /// [feedback] is in the chat.
  Future<void> pick(
    WidgetTester tester,
    AppHarness harness,
    String option,
    String feedback,
  ) async {
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(option));
    await waitForIdle(tester, harness);
    await tester.tap(find.text(option));
    await pumpUntilFound(
      tester,
      find.textContaining(feedback, findRichText: true),
    );
    await waitForIdle(tester, harness);
  }

  /// The open [question] in the chat, and no quiz; the student answers it in
  /// the composer.
  Future<void> answerInChat(
    WidgetTester tester,
    AppHarness harness,
    String question,
    String answer,
  ) async {
    await pumpUntilFound(
      tester,
      find.textContaining(question, findRichText: true),
    );
    await waitForIdle(tester, harness);
    expect(find.byType(QuizView), findsNothing);
    final composer = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, composer);
    await tester.tap(composer);
    await tester.pump();
    await tester.enterText(composer, answer);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
  }

  /// What the app asked the model for in request [i]: its type and target.
  ({String type, String? target}) asked(ScriptedLlm llm, int i) {
    final input = jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;
    final los = (input['target_los'] as List?)?.cast<Map>();
    return (
      type: input['request_type'] as String,
      target: los == null || los.isEmpty ? null : los.first['id'] as String,
    );
  }

  Map<String, dynamic> belief(AppHarness harness, String loId) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_$loId']!;

  List<Map<String, dynamic>> turns(AppHarness harness) {
    final all = harness.cosmos['turn_history'].docs.values.toList()
      ..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );
    return all;
  }

  testWidgets('a right pick weighs half; the next question on that LO is an '
      'open one in the chat, not a quiz, while a fresh LO still starts with a '
      'pick; the right open answer counts, and the stamp waits for the '
      'bar', (tester) async {
    final llm = ScriptedLlm([
      _mcqReply('Wat doet print()?', [
        kPrintWrong,
        kPrintKey,
        'Het rekent',
      ], 'B'),
      _mcqGrade('Juist.', 'correct', 'lo-print', 'positive'),
      _mcqReply('Waarom staat tekst tussen aanhalingstekens?', [
        kQuoteKey,
        kQuoteWrong,
        'Dat hoeft niet',
      ], 'A'),
      _mcqGrade('Nee, het is geen opmaak.', 'wrong', 'lo-quote', 'negative'),
      _openQuestion(kOpenQuestion),
      _openRight('Helemaal juist, in je eigen woorden.', 'lo-print'),
      _mcqReply('Wat is "3" in Python?', [
        'Tekst',
        'Een getal',
        'Een lijst',
      ], 'A'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [
          _print(['lo-print', 'lo-quote']),
        ],
      },
    );
    await openPractice(tester, harness);

    // 1. Cold start: a pick on lo-print, right — half the weight.
    await pick(tester, harness, kPrintKey, 'Juist.');
    expect(asked(llm, 0), (type: 'multiple_choice', target: 'lo-print'));
    await pumpUntil(tester, () => turns(harness).length == 1);
    final first = turns(harness).single;
    expect(first['questionType'], 'mcQuestion');
    expect(
      ((first['appliedSignals'] as List).single as Map)['alphaDelta'],
      closeTo(1.0, 1e-9),
    );
    var print = belief(harness, 'lo-print');
    expect(print['alpha'], closeTo(2.0, 1e-9)); // 1 + 2.0 × 0.5
    expect(print['ownQuestionsRight'], 1);
    expect(print['ownQuestionsRightNonMcq'], 0);

    // 2. lo-quote has no right own question: a pick is the way in. A wrong
    //    pick weighs as any wrong answer.
    await tester.tap(find.text('Next →'));
    await pick(tester, harness, kQuoteWrong, 'geen opmaak');
    expect(asked(llm, 2), (type: 'multiple_choice', target: 'lo-quote'));
    expect(belief(harness, 'lo-quote')['beta'], closeTo(3.0, 1e-9));

    // 3. Back on lo-print: its right non-pick is missing, so the question is
    //    an open one, in the chat.
    await tester.tap(find.text('Next →'));
    await answerInChat(
      tester,
      harness,
      kOpenQuestion,
      'Het zet de tekst op het scherm.',
    );
    await pumpUntil(
      tester,
      () => turns(harness).length == 3,
      timeout: const Duration(seconds: 30),
      reason: 'the open answer was never recorded',
    );
    expect(asked(llm, 4), (type: 'socratic_question', target: 'lo-print'));
    expect(turns(harness).last['questionType'], 'socraticQuestion');
    print = belief(harness, 'lo-print');
    expect(print['ownQuestionsRight'], 2);
    expect(print['ownQuestionsRightNonMcq'], 1);
    // Forgotten to (1.7, 1), + 2.0: μ 0.79 on evidence 4.7 — no stamp.
    expect(print['alpha'], closeTo(3.7, 1e-3));
    expect(print.containsKey('firstMasteredAt'), isFalse);

    // 4. The next exercise: lo-quote, still without a right own question,
    //    so a pick again.
    await pumpUntil(
      tester,
      () => llm.remaining == 0,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise was never asked for',
    );
    expect(asked(llm, 6), (type: 'multiple_choice', target: 'lo-quote'));
    await pumpUntilFound(tester, find.byType(QuizView));

    await harness.dispose(tester);
  });

  testWidgets('picks alone are no stamp: an LO over the bar on four right '
      'picks is not mastered, the session asks it an open question, and its '
      'right answer stamps it and reaches the subgoal', (tester) async {
    final now = DateTime.now().toUtc();
    final llm = ScriptedLlm([
      _openQuestion(kOpenQuestion),
      _openRight('Juist.', 'lo-print'),
      llmEnvelope(
        text: 'Sam kent print().',
        meta:
            '{"type":"status_summary","stats":{"hints_used":0,'
            '"common_issues":[],"last_exercise_type":"socratic_question"}}',
      ),
      completeCodeReply(text: 'Nu een variabele.', code: kNextSubgoal),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [
          _print(['lo-print']),
        ],
        'lo_beliefs': [
          // Four right picks on record and nothing else: (4.9, 1), μ 0.83
          // on evidence 5.9 — mastered and stamped before 1.1.
          {
            'id': '${kStudentUid}_s1_lo-print',
            'type': 'lo_belief',
            'uid': kStudentUid,
            'subgoalId': 's1',
            'loId': 'lo-print',
            'alpha': 4.9,
            'beta': 1.0,
            'lastUpdatedAt': now.toIso8601String(),
            'lastQuestionType': 'mcQuestion',
            'lastPositiveAtCalibratedAt': now.toIso8601String(),
            'highestPositiveDifficulty': 'medium',
            'recentNegativesAtCalibrated': 0,
            'ownQuestions': 4,
            'ownQuestionsRight': 4,
            'ownQuestionsRightNonMcq': 0,
          },
        ],
      },
    );
    await openPractice(tester, harness);

    await answerInChat(tester, harness, kOpenQuestion, 'Het toont tekst.');
    expect(asked(llm, 0), (type: 'socratic_question', target: 'lo-print'));

    // The right open answer is the fourth condition: the stamp, and "Print"
    // is reached. Tap the celebration away, as a student would.
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);
    await pumpUntil(
      tester,
      () =>
          find.byType(CodeField).evaluate().isNotEmpty &&
          tester.widget<CodeField>(find.byType(CodeField)).controller.text ==
              kNextSubgoal,
      timeout: const Duration(seconds: 30),
      reason: "the next subgoal's exercise never reached the editor",
    );
    await waitForIdle(tester, harness);

    final print = belief(harness, 'lo-print');
    expect(print['firstMasteredAt'], print['lastUpdatedAt']);
    expect(print['ownQuestionsRight'], 5);
    expect(print['ownQuestionsRightNonMcq'], 1);
    final turn = turns(harness).single;
    expect(turn['questionType'], 'socraticQuestion');
    expect(turn['subgoalAdvanced'], isTrue);
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s1']!['advancedAt'],
      isA<String>(),
    );
    expect(llm.remaining, 0);

    await harness.dispose(tester);
  });
}
