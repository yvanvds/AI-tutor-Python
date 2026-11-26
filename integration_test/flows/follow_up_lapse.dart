// End-to-end (#340): a follow-up the student leaves open lapses when the
// next question comes, and the answer to that question is its own.
//
// A follow-up is answered in the chat. "Next" under a quiz whose grade
// asked one puts the next question up first. The follow-up used to stay
// open through it, and the answer to the next question was recorded as the
// follow-up's: `isFollowUp`, no `questionId`, the follow-up's `askedAt`,
// the follow-up as its question in `turn_content`, and never into the
// question bank. In the class data of 6EWI and 6WEWI it happened to 15
// students, on every build from 2.8.0 to 2.16.0.
//
// Now the next question's answer is a turn of its own: no follow-up, the ID
// and the moment of that question, its text in `turn_content`, and into the
// bank when it was answered right. (A follow-up answered in the chat while
// it is open stays one: `follow_up_after_partial`. Code sent from the
// editor next to the follow-up of a code exercise brought the next exercise
// too, until #349 made it the follow-up's answer: `follow_up_code_answer`.)
//
// Real app, real navigation, real quiz view with its "Next" button, real
// TutorService → conductor → turn history, turn content and question bank
// services → in-memory Cosmos. Only the model is scripted (`ScriptedLlm`,
// raw assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/follow_up_lapse.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _followUp =
    'Hoe pas je de code aan zodat je de laatste kleur met een a bewaart?';

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

/// The grade of a pick on [loId], right, with [followUp] when given.
String _rightPick(String text, String loId, {String? followUp}) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'correct',
    'loSignals': [_signal(loId, 'positive')],
    if (followUp != null) 'followUp': {'question': followUp},
  }),
);

/// "Print" without its lesson, so the leerpad opens the practice view, with
/// the LOs [ids] of [kind].
Map<String, dynamic> _print(List<String> ids, {required String kind}) =>
    goalDoc(
      id: 's1',
      title: 'Print',
      parentId: 'r1',
      order: 1000,
      objectives: [
        for (final id in ids)
          {...objective(id, 'Use print() ($id)'), 'kind': kind},
      ],
    );

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

  Future<void> waitForFollowUp(WidgetTester tester, AppHarness harness) async {
    await pumpUntilFound(
      tester,
      find.textContaining('laatste kleur met een a', findRichText: true),
    );
    await waitForIdle(tester, harness);
  }

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

  /// The `turn_content` doc of [turn], once it is written.
  Future<Map<String, dynamic>> contentOf(
    WidgetTester tester,
    AppHarness harness,
    Map<String, dynamic> turn,
  ) async {
    final contents = harness.cosmos['turn_content'];
    final id = turn['id'] as String;
    await pumpUntil(
      tester,
      () => contents[id] != null,
      reason: 'no content was written for the oefening',
    );
    return contents[id]!;
  }

  /// The bank question [id], once it is written.
  Future<void> waitForBanked(
    WidgetTester tester,
    AppHarness harness,
    String id,
  ) => pumpUntil(
    tester,
    () => harness.cosmos['questions'][id] != null,
    reason: 'the question answered right never went into the bank',
  );

  /// What the app asked the model for in request [i].
  String requestType(ScriptedLlm llm, int i) =>
      (jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>)['request_type']
          as String;

  testWidgets('"Next" under a quiz whose follow-up is open: the pick on the '
      'next quiz is that quiz\'s own answer — no follow-up, its ID and '
      'moment, its text in turn_content, and into the bank', (tester) async {
    const nextPrompt = 'Wat toont print("31")?';
    final llm = ScriptedLlm([
      _mcqReply('Wat doet print()?', [
        'Het slaat tekst op',
        'Het toont tekst op het scherm',
        'Het rekent',
      ], 'B'),
      _rightPick('Juist.', 'lo-print', followUp: _followUp),
      _mcqReply(nextPrompt, ['31', '"31"', 'Error'], 'A'),
      _rightPick('Juist: de tekst 31.', 'lo-quote'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [
          _print(['lo-print', 'lo-quote'], kind: 'recall'),
        ],
      },
    );
    await openPractice(tester, harness);

    // 1. The quiz, picked right; its grade asks a follow-up in the chat.
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text('Het toont tekst op het scherm'));
    await waitForIdle(tester, harness);
    await tester.tap(find.text('Het toont tekst op het scherm'));
    await waitForFollowUp(tester, harness);
    await waitForTurns(tester, harness, 1);

    // 2. The student leaves the follow-up and clicks "Next".
    final beforeNext = DateTime.now().toUtc();
    await tester.tap(find.text('Next →'));
    await pumpUntilFound(
      tester,
      find.textContaining(nextPrompt, findRichText: true),
    );
    await pumpUntilFound(tester, find.text('"31"'));
    await waitForIdle(tester, harness);
    expect(requestType(llm, 2), 'multiple_choice');

    // 3. They pick on the next quiz: that is its answer.
    await tester.tap(find.text('31'));
    await waitForTurns(tester, harness, 2);
    expect(requestType(llm, 3), 'mcq_answer');
    expect(llm.remaining, 0);

    final turn = turns(harness)[1];
    expect(turn['isFollowUp'], isFalse);
    expect(turn['chainDepth'], 0);
    expect(turn['questionType'], 'mcQuestion');
    expect(turn['targetLOIds'], ['lo-quote']);
    final id = turn['questionId'] as String?;
    expect(id, isNotNull, reason: 'the question on screen has an ID');
    expect(
      DateTime.parse(turn['askedAt'] as String).isBefore(beforeNext),
      isFalse,
      reason: 'asked when the next quiz came, not when the follow-up did',
    );

    final content = await contentOf(tester, harness, turn);
    expect(content['isFollowUp'], isFalse);
    expect((content['question'] as Map)['text'], nextPrompt);
    expect((content['question'] as Map)['questionId'], id);
    expect(content['answer'], {'picked': '31'});
    await waitForBanked(tester, harness, id!);

    await harness.dispose(tester);
  });
}
