// End-to-end (#349): code sent from the editor while a follow-up is open is
// the answer to that follow-up.
//
// After a code exercise the grader may ask a follow-up like "how would you
// change the code so that…". The student answers it in the editor as
// readily as in the chat, and presses "Send to tutor". That code went out
// as `submit_code` without a plan: graded, the feedback in the chat, but
// recorded nowhere — no `turn_history` record, nothing in `turn_content`,
// its cost on the next exercise's record — and the next exercise came.
//
// Now it goes out as the chat's answer does (`follow_up_answer`, with the
// follow-up and the code) and becomes the follow-up's record: `isFollowUp`,
// the follow-up as its question in `turn_content`, the code as its answer.
// The next exercise comes after it, as after a follow-up answered in the
// chat, and the code handed in on that one is its own answer.
//
// Real app, real navigation, real practice view with its editor and send
// button, real chat, real TutorService → conductor → turn history, turn
// content and question bank services → in-memory Cosmos. Only the model is
// scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/follow_up_code_answer.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
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
    'Hoe pas je de code aan zodat je de laatste kleur bewaart?';

Map<String, String> _signal(String loId, String kind) => {
  'subgoalId': 's1',
  'loId': loId,
  'signal': kind,
  'strength': 'strong',
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

  /// What the app sent the model in request [i].
  Map<String, dynamic> sent(ScriptedLlm llm, int i) =>
      jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>;

  testWidgets('code sent from the editor while the follow-up of a code '
      'exercise is open answers that follow-up: a follow-up record with the '
      'code as its answer, then the next exercise, whose code is its own '
      'answer', (tester) async {
    const first = 'kleur = ___\nprint(kleur)';
    const firstAnswer = 'kleur = "rood"\nprint(kleur)';
    const followUpCode =
        'for kleur in kleuren:\n    laatste = kleur\nprint(laatste)';
    const next = 'warmste = ___\nprint(warmste)';
    const nextAnswer = 'warmste = 31\nprint(warmste)';
    const followUpFeedback = 'Juist: zo bewaar je de laatste kleur.';
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
      // The code sent next to the follow-up: graded as its answer.
      llmEnvelope(
        text: followUpFeedback,
        meta: jsonEncode({
          'type': 'socratic_feedback',
          'overallQuality': 'correct',
          'loSignals': [_signal('lo-print', 'positive')],
        }),
      ),
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
          // "Print" without its lesson, so the leerpad opens the practice
          // view.
          goalDoc(
            id: 's1',
            title: 'Print',
            parentId: 'r1',
            order: 1000,
            objectives: [
              {
                ...objective('lo-print', 'Use print() to show text'),
                'kind': 'apply',
              },
            ],
          ),
        ],
      },
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    String editorText() =>
        tester.widget<CodeField>(find.byType(CodeField)).controller.text;
    Future<void> waitForExercise(String code) => pumpUntil(
      tester,
      () => editorText() == code,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise "$code" never reached the editor',
    );
    Future<void> sendFromEditor(String code) async {
      harness.container
              .read(codeServiceProvider(SessionMode.practice))
              .controller
              .text =
          code;
      await tester.pump();
      await tester.tap(find.byTooltip('Send to tutor'));
    }

    // 1. The code exercise, "partial", with a follow-up in the chat.
    await waitForExercise(first);
    await waitForIdle(tester, harness);
    final beforeFirst = DateTime.now().toUtc();
    await sendFromEditor(firstAnswer);
    await pumpUntilFound(
      tester,
      find.textContaining('laatste kleur bewaart', findRichText: true),
    );
    await waitForIdle(tester, harness);
    await waitForTurns(tester, harness, 1);
    expect(sent(llm, 1)['request_type'], 'submit_code');

    // 2. The student changes the code in the editor and sends it, instead
    //    of answering in the chat: it is the answer to the follow-up.
    final beforeFollowUpAnswer = DateTime.now().toUtc();
    await sendFromEditor(followUpCode);
    await waitForTurns(tester, harness, 2);
    final request = sent(llm, 2);
    expect(request['request_type'], 'follow_up_answer');
    expect(request['follow_up_question'], _followUp);
    expect(request['code'], followUpCode);
    expect(request.containsKey('answer'), isFalse);

    final followUp = turns(harness)[1];
    expect(followUp['isFollowUp'], isTrue);
    expect(followUp['chainDepth'], 1);
    expect(followUp['targetLOIds'], ['lo-print']);
    expect(followUp['overallQuality'], 'correct');
    expect(followUp['questionId'], isNull);
    final askedAt = DateTime.parse(followUp['askedAt'] as String);
    expect(
      askedAt.isBefore(beforeFirst),
      isFalse,
      reason: 'asked when the follow-up came',
    );
    expect(
      askedAt.isBefore(beforeFollowUpAnswer),
      isTrue,
      reason: 'the follow-up\'s own moment, not a later question\'s',
    );
    final followUpContent = await contentOf(tester, harness, followUp);
    expect(followUpContent['isFollowUp'], isTrue);
    expect(followUpContent['question'], {'text': _followUp});
    expect(followUpContent['answer'], {'code': followUpCode});
    expect(followUpContent['feedback'], followUpFeedback);
    await pumpUntilFound(
      tester,
      find.textContaining(followUpFeedback, findRichText: true),
    );

    // The next exercise comes, as after a follow-up answered in the chat.
    await waitForExercise(next);
    await waitForIdle(tester, harness);

    // 3. The code handed in on the next exercise is its own answer.
    await sendFromEditor(nextAnswer);
    await waitForTurns(tester, harness, 3);
    expect(sent(llm, 4)['request_type'], 'submit_code');
    await waitForExercise('print(___)');
    expect(llm.remaining, 0);

    final own = turns(harness)[2];
    expect(own['isFollowUp'], isFalse);
    expect(own['chainDepth'], 0);
    final id = own['questionId'] as String?;
    expect(id, isNotNull, reason: 'the exercise on screen has an ID');
    final ownContent = await contentOf(tester, harness, own);
    expect(ownContent['isFollowUp'], isFalse);
    expect(ownContent['question'], {
      'text': 'Zoek de warmste temperatuur.',
      'code': next,
      'questionId': id,
    });
    expect(ownContent['answer'], {'code': nextAnswer});

    await harness.dispose(tester);
  });
}
