// End-to-end (#340): a follow-up the student leaves open lapses when the
// next question comes, and the answer to that question is its own.
//
// A follow-up is answered in the chat. Two ways put the next question up
// first: "Next" under a quiz whose grade asked one, and code sent from the
// editor next to the follow-up of a code exercise — that grade has nothing
// to be recorded on and asks for the next exercise. The follow-up used to
// stay open through both, and the answer to the next question was recorded
// as the follow-up's: `isFollowUp`, no `questionId`, the follow-up's
// `askedAt`, the follow-up as its question in `turn_content`, and never into
// the question bank. In the class data of 6EWI and 6WEWI it happened to 15
// students, on every build from 2.8.0 to 2.16.0.
//
// Now the next question's answer is a turn of its own: no follow-up, the ID
// and the moment of that question, its text in `turn_content`, and into the
// bank when it was answered right. (A follow-up answered in the chat while
// it is open stays one: `follow_up_after_partial`.)
//
// Real app, real navigation, real quiz view with its "Next" button, real
// editor with its send button, real TutorService → conductor → turn
// history, turn content and question bank services → in-memory Cosmos.
// Only the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/follow_up_lapse.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
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

  testWidgets('code sent from the editor next to the follow-up of a code '
      'exercise brings the next exercise: the code handed in on it is its '
      'own answer, not the follow-up\'s', (tester) async {
    const first = 'kleur = ___\nprint(kleur)';
    const next = 'warmste = ___\nprint(warmste)';
    const answer = 'warmste = 31\nprint(warmste)';
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Bewaar een kleur.', code: first),
      llmEnvelope(
        text: 'Bijna: dat is de eerste kleur.',
        meta: jsonEncode({
          'type': 'code_feedback',
          'suggestion': '',
          'overallQuality': 'partial',
          'loSignals': [_signal('lo-print', 'positive')],
          'followUp': {'question': _followUp},
        }),
      ),
      // The code sent next to the follow-up: graded without an exercise
      // to record it on, and the next exercise is asked for.
      codeFeedbackReply(text: 'Dat werkt ook.', quality: 'correct'),
      completeCodeReply(text: 'Zoek de warmste temperatuur.', code: next),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-print', 'positive')],
      ),
      completeCodeReply(text: 'Nog een.', code: 'print(___)'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'goals': [
          _print(['lo-print'], kind: 'apply'),
        ],
      },
    );
    await openPractice(tester, harness);

    String editorText() =>
        tester.widget<CodeField>(find.byType(CodeField)).controller.text;
    Future<void> waitForExercise(String code) => pumpUntil(
      tester,
      () => editorText() == code,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise "$code" never reached the editor',
    );
    void typeInEditor(String code) =>
        harness.container
                .read(codeServiceProvider(SessionMode.practice))
                .controller
                .text =
            code;

    // 1. The code exercise, "partial", with a follow-up in the chat.
    await waitForExercise(first);
    await waitForIdle(tester, harness);
    typeInEditor('kleur = "rood"\nprint(kleur)');
    await tester.pump();
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForFollowUp(tester, harness);
    await waitForTurns(tester, harness, 1);

    // 2. Instead of answering in the chat, the student changes the code
    //    and sends it. The next exercise comes.
    final beforeSend = DateTime.now().toUtc();
    typeInEditor('kleur = "oranje"\nprint(kleur)');
    await tester.pump();
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(next);
    await waitForIdle(tester, harness);
    expect(requestType(llm, 2), 'submit_code');
    expect(turns(harness), hasLength(1), reason: 'nothing to record it on');

    // 3. The code handed in on the next exercise is its answer.
    typeInEditor(answer);
    await tester.pump();
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 2);
    expect(requestType(llm, 4), 'submit_code');
    await waitForExercise('print(___)');
    expect(llm.remaining, 0);

    final turn = turns(harness)[1];
    expect(turn['isFollowUp'], isFalse);
    expect(turn['chainDepth'], 0);
    final id = turn['questionId'] as String?;
    expect(id, isNotNull, reason: 'the exercise on screen has an ID');
    expect(
      DateTime.parse(turn['askedAt'] as String).isBefore(beforeSend),
      isFalse,
      reason: 'asked when the next exercise came, not when the follow-up did',
    );

    final content = await contentOf(tester, harness, turn);
    expect(content['isFollowUp'], isFalse);
    expect(content['question'], {
      'text': 'Zoek de warmste temperatuur.',
      'code': next,
      'questionId': id,
    });
    expect(content['answer'], {'code': answer});
    await waitForBanked(tester, harness, id!);

    await harness.dispose(tester);
  });
}
