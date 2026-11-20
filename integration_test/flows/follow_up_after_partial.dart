// End-to-end (#326, formula 1.1.3): a right follow-up after a "partial"
// own question counts that own question as answered right.
//
// The follow-up after "partial" is there to let the student finish the
// answer. Until 1.1.3 it could never count as a right own question (§4.1
// condition 4: two of them, one no multiple choice), so an LO one right own
// question short of its stamp stayed open after the student finished the
// answer, and the tutor asked it again. Now the own question counts once its
// follow-up is right (CONDUCTOR_POLICY §6.2).
//
// On "Print" with two LOs. lo-a is over the bar on its belief, with one
// right own question that was no pick — condition 4 wants a second one:
//   1. lo-a answered "partial", with a follow-up  → still one right own
//      question, not mastered, the share 0
//   2. the follow-up, right                       → two: mastered, stamped,
//      the share 0.5, its segment full (0 to go)
//   3. the next question is on lo-b, not on lo-a again
//
// Real app, real navigation, real practice view, editor and chat, real
// TutorService → conductor → belief math → Cosmos services. Only the model
// is scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/follow_up_after_partial.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/subgoal_progress_bar.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const List<String> _exercises = [
  'print(___)',
  'print("a", ___)',
  'print(1, ___)',
];

Map<String, String> _signal(
  String loId,
  String kind, {
  String strength = 'strong',
}) => {'subgoalId': 's1', 'loId': loId, 'signal': kind, 'strength': strength};

/// "Print" without its lesson, so the leerpad opens the editor, with two
/// LOs.
Map<String, dynamic> _printGoal() => goalDoc(
  id: 's1',
  title: 'Print',
  parentId: 'r1',
  order: 1000,
  objectives: [
    objective('lo-a', 'Print a sentence'),
    objective('lo-b', 'Print several values at once'),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Future<void> waitForExercise(WidgetTester tester, String code) => pumpUntil(
    tester,
    () => editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise "$code" never reached the editor',
  );

  List<Map<String, dynamic>> turns(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList()..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );

  Future<void> waitForTurns(WidgetTester tester, AppHarness harness, int n) =>
      pumpUntil(
        tester,
        () => harness.cosmos['turn_history'].docs.length == n,
        timeout: const Duration(seconds: 30),
        reason: 'turn $n was never recorded',
      );

  bool masteredAfter(Map<String, dynamic> turn, String loId) =>
      (turn['loStatusAfter'] as List).cast<Map>().firstWhere(
            (l) => l['loId'] == loId,
          )['mastered']
          as bool;

  /// The right answers to go in each segment of the bar (#325).
  List<int> segments(WidgetTester tester) => [
    for (final s in tester.widgetList<LoSegment>(find.byType(LoSegment)))
      s.entry.toGo,
  ];

  testWidgets('a "partial" own question finished right in its follow-up '
      'counts as a right own question: the LO is mastered and the tutor '
      'moves on', (tester) async {
    final written = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Print een zin.', code: _exercises[0]),
      // 1. lo-a "partial", with a follow-up to finish the answer.
      llmEnvelope(
        text: 'Bijna: de aanhalingstekens ontbreken.',
        meta: jsonEncode({
          'type': 'code_feedback',
          'suggestion': '',
          'overallQuality': 'partial',
          'loSignals': [_signal('lo-a', 'positive', strength: 'moderate')],
          'followUp': {'question': 'Wat moet er rond de tekst staan?'},
        }),
      ),
      // 2. The follow-up, right: weak, 0.5 (§6.2) — and the own question
      //    counts as right.
      llmEnvelope(
        text: 'Juist: aanhalingstekens.',
        meta: jsonEncode({
          'type': 'socratic_feedback',
          'overallQuality': 'correct',
          'loSignals': [_signal('lo-a', 'positive')],
        }),
      ),
      completeCodeReply(text: 'Print twee waarden.', code: _exercises[1]),
      // 3. Not right, so the subgoal stays open and the flow ends here.
      codeFeedbackReply(
        text: 'Niet juist: er ontbreekt een waarde.',
        quality: 'wrong',
        loSignals: [_signal('lo-b', 'negative', strength: 'weak')],
      ),
      completeCodeReply(text: 'Nog eens.', code: _exercises[2]),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [_printGoal()],
        'lo_beliefs': [
          // Over the bar on its belief, a positive at calibration, one right
          // own question that was no pick: condition 4 wants a second.
          LoBelief(
            subgoalId: 's1',
            loId: 'lo-a',
            alpha: 8,
            beta: 1,
            lastUpdatedAt: written,
            lastQuestionType: 'socraticQuestion',
            lastPositiveAtCalibratedAt: written,
            highestPositiveDifficulty: QuestionDifficulty.medium,
            lastProbedAt: written,
            ownQuestions: 1,
            ownQuestionsRight: 1,
            ownQuestionsRightNonMcq: 1,
          ).toMap(uid: kStudentUid),
          // Seen from the side only, never asked: a higher mean than lo-a,
          // so lo-a goes first.
          LoBelief(
            subgoalId: 's1',
            loId: 'lo-b',
            alpha: 9,
            beta: 1,
            lastUpdatedAt: written,
            ownQuestions: 0,
            ownQuestionsRight: 0,
            ownQuestionsRightNonMcq: 0,
          ).toMap(uid: kStudentUid),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, _exercises[0]);

    double cachedShare() =>
        ((harness.cosmos['progress'].docs['${kStudentUid}_s1']?['progress']
                    as num?) ??
                0)
            .toDouble();
    Map<String, dynamic> storedA() =>
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-a']!;

    // 1. The own question, "partial": one right own question still.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 1);
    final own = turns(harness)[0];
    expect(own['targetLOIds'], ['lo-a']);
    expect(own['overallQuality'], 'partial');
    expect(masteredAfter(own, 'lo-a'), isFalse);
    expect(own['subgoalProgressAfter'], 0.0);
    expect(storedA()['ownQuestions'], 2);
    expect(storedA()['ownQuestionsRight'], 1);
    expect(storedA()['firstMasteredAt'], isNull);
    expect(segments(tester).first, greaterThan(0));

    // 2. The follow-up comes in the chat; the student finishes the answer.
    await pumpUntilFound(
      tester,
      find.textContaining('Wat moet er rond', findRichText: true),
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
    await tester.enterText(composer, 'Aanhalingstekens.');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await waitForTurns(tester, harness, 2);

    final followUp = turns(harness)[1];
    expect(followUp['isFollowUp'], isTrue);
    expect(followUp['overallQuality'], 'correct');
    // The own question counts as right now: two, both no pick — mastered,
    // stamped on this follow-up, and the share of the subgoal rises.
    final after = storedA();
    expect(after['ownQuestionsRight'], 2);
    expect(after['ownQuestionsRightNonMcq'], 2);
    // The follow-up is no own question itself.
    expect(after['ownQuestions'], 2);
    expect(after['firstMasteredAt'], isNotNull);
    expect(masteredAfter(followUp, 'lo-a'), isTrue);
    expect(followUp['subgoalProgressAfter'], 0.5);
    await pumpUntil(
      tester,
      () => cachedShare() == 0.5,
      reason: 'the mastered LO never reached the cached share',
    );
    // The student sees it: lo-a's segment is full, 0 to go.
    await pumpUntil(tester, () {
      final s = segments(tester);
      return s.isNotEmpty && s.first == 0;
    }, reason: 'lo-a\'s segment never filled');

    // 3. The next question is on lo-b: lo-a is not asked again.
    await waitForExercise(tester, _exercises[1]);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 3);
    expect(turns(harness)[2]['targetLOIds'], ['lo-b']);
    expect(masteredAfter(turns(harness)[2], 'lo-a'), isTrue);

    await waitForExercise(tester, _exercises[2]);
    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
