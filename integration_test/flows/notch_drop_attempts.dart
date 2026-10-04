// End-to-end (#227): a student on `hard` who answers an LO "partly right"
// again and again — the question and the follow-up on it — gets the next
// question on that LO one level lower, `medium`; a right answer there, and
// the question after it is back on `hard`.
//
// The pattern of the issue: every "partial" came with a positive signal on
// the asked LO, so the two-strike rule of CONDUCTOR_POLICY §2.3 never
// counted a strike, and the follow-ups stay out of the calibration window
// (§6.2) — nothing lowered the questions. The second rule counts attempts
// on the LO in the session, follow-ups included, until a `correct`.
//
// What the student gets is the question the model is asked for, so the
// level is checked where the app asks for it — the `difficulty` of each
// question request it sends — and on the `turn_history` docs: the lower
// question's turn says `medium`, that the notch dropped, and which rule did
// it (`notchDropRules`).
//
// Real app, real navigation, real practice view, editor and chat composer,
// real TutorService follow-up bookkeeping → conductor → Cosmos services.
// Only the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/notch_drop_attempts.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const List<String> _exercises = [
  'if a > 0 ___ b > 0:\n    print("beide")',
  'if x < 10 ___ y < 10:\n    print("klein")',
  'if ___ > 0:\n    print("positief")',
  'if p ___ q:\n    print("allebei")',
];

Map<String, String> _signal(String kind, String strength) => {
  'subgoalId': 's1',
  'loId': 'lo-print',
  'signal': kind,
  'strength': strength,
};

/// A "partial" on the code, with a positive on the asked LO — as the grader
/// gave it in #227 — and a follow-up question.
String _partialWithFollowUp(String text, String followUp) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'code_feedback',
    'suggestion': '',
    'overallQuality': 'partial',
    'loSignals': [_signal('positive', 'moderate')],
    'followUp': {'question': followUp},
  }),
);

/// The grade of a follow-up answer that is not right either.
String _followUpNotRight(String text) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'socratic_feedback',
    'overallQuality': 'partial',
    'loSignals': [_signal('negative', 'weak')],
  }),
);

/// The student on `hard`, with a window of ten right answers there — the
/// two "partial" ones of this flow demote nothing (§5.2).
Map<String, dynamic> _hardStudent() {
  final t0 = DateTime.now().toUtc().subtract(const Duration(days: 2));
  return {
    ...accountDoc(studentIdentity),
    'calibration': {
      'difficulty': 'hard',
      'recentAnswers': [
        for (var i = 0; i < 10; i++)
          {
            'quality': 'correct',
            'difficulty': 'hard',
            'at': t0.add(Duration(minutes: i)).toIso8601String(),
          },
      ],
      'recentQuestionTypes': const <String>[],
    },
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Future<void> waitForExercise(WidgetTester tester, int i) => pumpUntil(
    tester,
    () => editorText(tester) == _exercises[i],
    timeout: const Duration(seconds: 30),
    reason: 'exercise ${i + 1} never reached the editor',
  );

  Future<void> waitForIdle(WidgetTester tester, AppHarness harness) =>
      pumpUntil(
        tester,
        () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      );

  /// The student answers the follow-up [question] in the chat.
  Future<void> answerFollowUp(
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

  /// The level of every question the app asked the model for, in order.
  List<String> askedLevels(ScriptedLlm llm) => [
    for (final input in llm.sentInputs)
      if (jsonDecode(input) case {
        'request_type': 'complete_code' || 'write_code',
        'difficulty': final String level,
      })
        level,
  ];

  testWidgets('four attempts on an LO without a right answer — "partial" '
      'questions and follow-ups — and the next question on it is asked a '
      'level lower; a right answer there, and the next is back on hard', (
    tester,
  ) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Vul de operator in.', code: _exercises[0]),
      _partialWithFollowUp('Bijna: de operator ontbreekt.', 'Wat doet and?'),
      _followUpNotRight('Niet helemaal: and wil dat beide waar zijn.'),
      completeCodeReply(text: 'Nog een keer.', code: _exercises[1]),
      _partialWithFollowUp('Bijna: kijk naar de voorwaarde.', 'En or?'),
      _followUpNotRight('Niet helemaal: or wil dat een van beide waar is.'),
      completeCodeReply(text: 'Een eenvoudiger vraag.', code: _exercises[2]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('positive', 'strong')],
      ),
      completeCodeReply(text: 'Weer een moeilijke.', code: _exercises[3]),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'accounts': [_hardStudent()],
        // "Print" without its lesson, so the leerpad opens the editor.
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

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    // Two questions on hard, each answered "partial" and its follow-up not
    // right either: four attempts.
    await waitForExercise(tester, 0);
    await tester.tap(find.byTooltip('Send to tutor'));
    await answerFollowUp(tester, harness, 'Wat doet and?', 'Allebei waar.');
    await waitForExercise(tester, 1);
    await tester.tap(find.byTooltip('Send to tutor'));
    await answerFollowUp(tester, harness, 'En or?', 'Ook allebei.');

    // The third is asked a level lower…
    await waitForExercise(tester, 2);
    expect(askedLevels(llm), ['hard', 'hard', 'medium']);
    await tester.tap(find.byTooltip('Send to tutor'));

    // …and after a right answer there, the fourth is back on hard.
    await waitForExercise(tester, 3);
    expect(askedLevels(llm), ['hard', 'hard', 'medium', 'hard']);

    List<Map<String, dynamic>> turns() =>
        harness.cosmos['turn_history'].docs.values.toList()..sort(
          (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
        );
    await pumpUntil(
      tester,
      () => turns().length == 5,
      timeout: const Duration(seconds: 30),
      reason: 'not every answer was recorded',
    );
    final recorded = turns();
    expect(recorded.map((t) => t['isFollowUp']), [
      false,
      true,
      false,
      true,
      false,
    ]);
    expect(recorded.map((t) => t['overallQuality']), [
      'partial',
      'partial',
      'partial',
      'partial',
      'correct',
    ]);
    for (final t in recorded.take(4)) {
      expect(t['difficulty'], 'hard');
      final reason = t['selectionReason'] as Map;
      expect(reason['notchDropFired'], isFalse);
      expect(reason.containsKey('notchDropRules'), isFalse);
    }
    final lower = recorded.last;
    expect(lower['difficulty'], 'medium');
    final reason = lower['selectionReason'] as Map;
    expect(reason['notchDropFired'], isTrue);
    expect(reason['notchDropRules'], ['attemptsWithoutCorrect']);
    // The student's level never moved: this LO only.
    expect(recorded.map((t) => t['calibrationAfter']).toSet(), {'hard'});
    // The right answer weighs as what it was, medium (§3.2): a strong
    // positive is 2.0 × 1.0 there, where hard would have made it 2.8.
    final applied = (lower['appliedSignals'] as List).single as Map;
    expect(applied['loId'], 'lo-print');
    expect(applied['alphaDelta'] as num, closeTo(2.0, 1e-6));

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
