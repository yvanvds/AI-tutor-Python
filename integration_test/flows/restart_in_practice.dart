// End-to-end: the restart in the chat header ("Restart session"), pressed
// while the student is in Practice with an exercise on screen.
//
// The restart starts a fresh session: the chat is cleared and the exercise
// in flight is dropped, so the one on screen is no longer the tutor's
// question — the text of a code exercise left with the chat, and an answer
// would be graded against no plan. A fresh session in Practice brings its
// first exercise, as entering Practice does. Unlike "Continue" in the
// learning path, the restart changes neither the section nor the mode: no
// new practice view mounts to ask for it.
//
//   1. In the theory view the restart asks the model for nothing: its
//      exercise comes when the student goes to Practice.
//   2. In Practice it brings the next exercise of the new session: in the
//      editor, its text in the chat, on the subgoal the session is on.
//   3. The same on a Cosmos that answers slowly — every `progress` read
//      takes 300 ms, as a round trip to the school's does: the exercise
//      waits for the start's walk to its subgoal (#284) and comes.
//   4. A quiz on screen goes with the restart: the next exercise, a code
//      one, is in the editor, not behind the old quiz.
//
// Real app, real navigation, real Leerpad, chat header, practice view,
// quiz and editor, real TutorService → conductor → Cosmos services; only
// the model is scripted (`ScriptedLlm`) and, in 3, the `progress` reads
// are slowed.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/restart_in_practice.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kFirst = 'stad = ___\nprint("Welkom in " + stad)';
const String kFirstText = 'Vul de stad in.';
const String kSecond = 'naam = ___\nprint(naam)';
const String kSecondText = 'Geef naam een waarde.';
const String kQuizText = 'Wat toont dit programma?';

/// A multiple-choice question on [kQuizText].
String quizReply() => llmEnvelope(
  text: kQuizText,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'prompt': kQuizText,
    'code': 'naam = "Mira"\nprint(naam)',
    'options': [
      {'option': 'Mira'},
      {'option': 'naam'},
    ],
  }),
);

/// "Print" is done, so "Variables" — no lesson, so practice — is next.
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'advancedAt': '2026-08-03T10:00:00Z',
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// A container whose reads take [delay], as a round trip to Cosmos does.
class _SlowContainer implements CosmosContainer {
  _SlowContainer(this._inner, this.delay);

  final CosmosContainer _inner;
  final Duration delay;

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) async {
    await Future<void>.delayed(delay);
    return _inner.read(id, partitionKey: partitionKey);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) async {
    await Future<void>.delayed(delay);
    return _inner.query(
      sql,
      parameters: parameters,
      partitionKey: partitionKey,
      crossPartition: crossPartition,
    );
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => _inner.create(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => _inner.upsert(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
    String? ifMatch,
  }) => _inner.replace(id, doc, partitionKey: partitionKey, ifMatch: ifMatch);

  @override
  Future<void> delete(String id, {required Object partitionKey}) =>
      _inner.delete(id, partitionKey: partitionKey);

  @override
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) => _inner.executeBatch(ops, partitionKey: partitionKey);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The code in the editor; empty while a quiz takes its place.
  String editorText(WidgetTester tester) {
    final editor = find.byType(CodeField);
    if (editor.evaluate().isEmpty) return '';
    return tester.widget<CodeField>(editor).controller.text;
  }

  /// Whether [text] is in the chat panel.
  bool inChat(String text) => find
      .descendant(
        of: find.byType(ChatWidget),
        matching: find.textContaining(text, findRichText: true),
      )
      .evaluate()
      .isNotEmpty;

  /// Whether [text] is anywhere on screen — the quiz shows its question.
  bool onScreen(String text) =>
      find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

  /// The target LOs of the [i]th request the app sent the model.
  Iterable<String> targetsOf(ScriptedLlm llm, int i) =>
      ((jsonDecode(llm.sentInputs[i]) as Map<String, dynamic>)['target_los']
              as List)
          .cast<Map>()
          .map((lo) => '${lo['id']}');

  /// Practice on "Variables", reached the way a student does: "Continue"
  /// in the learning path; [onScreen] says when its first exercise is up.
  Future<void> practiceWithAnExercise(
    WidgetTester tester, {
    required bool Function() onScreen,
  }) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      onScreen,
      timeout: const Duration(seconds: 30),
      reason: 'the first exercise never came on screen',
    );
  }

  /// Presses the restart and waits for the next exercise — or, when none
  /// comes, for [patience] — then prints what the student sees.
  Future<void> restartAndWait(
    WidgetTester tester,
    ScriptedLlm llm, {
    Duration patience = const Duration(seconds: 10),
  }) async {
    await tester.tap(find.byTooltip('Restart session'));
    final until = DateTime.now().add(patience);
    while (DateTime.now().isBefore(until) &&
        !(editorText(tester) == kSecond && inChat(kSecondText))) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Settle whatever is still on its way.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print(
      'RESTART-PROBE editor=${editorText(tester).replaceAll('\n', r'\n')} '
      'quiz=${find.byType(QuizView).evaluate().isNotEmpty} '
      'firstInChat=${inChat(kFirstText)} quizOnScreen=${onScreen(kQuizText)} '
      'secondInChat=${inChat(kSecondText)} '
      'sent=${llm.sends} remaining=${llm.remaining}',
    );
  }

  void expectTheNextExercise(WidgetTester tester, ScriptedLlm llm) {
    expect(
      editorText(tester),
      kSecond,
      reason: 'the restart in Practice brought no new exercise',
    );
    expect(inChat(kSecondText), isTrue, reason: 'its text is not in the chat');
    expect(inChat(kFirstText), isFalse, reason: 'the chat was not cleared');
    expect(llm.sends, 2, reason: 'one request per exercise, no more');
    expect(llm.remaining, 0);
    expect(targetsOf(llm, 1), ['lo-var']);
  }

  AppHarness harnessFor(ScriptedLlm llm) => AppHarness(
    llm: llm,
    extraDocs: {
      'progress': [printDone()],
    },
  );

  testWidgets('the restart in the theory view asks for nothing; in Practice '
      'it brings the next exercise', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: kFirstText, code: kFirst),
      completeCodeReply(text: kSecondText, code: kSecond),
    ]);
    final harness = harnessFor(llm);
    await harness.boot(tester);

    // 1. The app opens on the theory view: a restart there asks nothing.
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.byTooltip('Restart session'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PracticeView), findsNothing);
    expect(llm.sends, 0, reason: 'the theory view asked for an exercise');

    // 2. In Practice the restart brings the next exercise.
    await practiceWithAnExercise(
      tester,
      onScreen: () => editorText(tester) == kFirst && inChat(kFirstText),
    );
    await restartAndWait(tester, llm);
    expectTheNextExercise(tester, llm);

    await harness.dispose(tester);
  });

  testWidgets('the restart in Practice, on a slow Cosmos, brings the next '
      'exercise', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: kFirstText, code: kFirst),
      completeCodeReply(text: kSecondText, code: kSecond),
    ]);
    final harness = harnessFor(llm);
    await harness.boot(tester);
    await practiceWithAnExercise(
      tester,
      onScreen: () => editorText(tester) == kFirst && inChat(kFirstText),
    );

    // 3. From now on every read of `progress` takes 300 ms.
    harness.cosmos.route(
      'progress',
      _SlowContainer(
        harness.cosmos['progress'].container,
        const Duration(milliseconds: 300),
      ),
    );
    await restartAndWait(tester, llm, patience: const Duration(seconds: 20));
    expectTheNextExercise(tester, llm);

    harness.cosmos.route('progress', null);
    await harness.dispose(tester);
  });

  testWidgets('a quiz on screen goes with the restart; the next exercise is '
      'in the editor', (tester) async {
    final llm = ScriptedLlm([
      quizReply(),
      completeCodeReply(text: kSecondText, code: kSecond),
    ]);
    final harness = harnessFor(llm);
    await harness.boot(tester);
    await practiceWithAnExercise(
      tester,
      onScreen: () =>
          find.byType(QuizView).evaluate().isNotEmpty && onScreen(kQuizText),
    );

    // 4. The restart, while the quiz waits for a pick.
    await restartAndWait(tester, llm);
    expect(
      find.byType(QuizView),
      findsNothing,
      reason: 'the quiz of the session before is still on screen',
    );
    expect(harness.container.read(activeMcqProvider), isNull);
    expect(onScreen(kQuizText), isFalse, reason: 'its question is still up');
    expect(editorText(tester), kSecond);
    expect(inChat(kSecondText), isTrue);
    expect(llm.sends, 2);
    expect(llm.remaining, 0);

    await harness.dispose(tester);
  });
}
