// End-to-end (#284): "Continue" ("Verder") in the learning path, pressed
// while the student is already in Practice, on a Cosmos that answers
// slowly — as the school's does, where every read is an HTTPS round trip.
//
// "Continue" switches to the session first and starts the new session
// after. The session's walk to the next subgoal clears the selection, then
// reads the goals and the progress docs; the practice view the switch
// mounts asks for its exercise one frame later. On the in-memory Cosmos of
// the other flows the walk is done long before that frame. On a slow one
// the request used to come while the selection was still empty: the chat
// said "There are no goals left to work on. Congratulations!", the old
// exercise stayed in the editor, and nothing asked again. An exercise asked
// for while a session is starting now waits for that start.
//
// Sam finished "Print", so "Variables" — no lesson, so practice — is next.
//
//   1. The first "Continue", from the theory view the app opens on, brings
//      the first exercise of "Variables" into the editor.
//   2. Every read of `progress` now takes 300 ms. Back to the learning path
//      and "Continue" again, from Practice: the next exercise of
//      "Variables" comes into the editor, and no "no goals left" pill.
//
// Real app, real navigation, real Leerpad, practice view and editor, real
// TutorService → conductor → Cosmos services; only the `progress` reads are
// slowed down, and the model is scripted (`ScriptedLlm`).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/verder_slow_cosmos.dart -d windows

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kFirst = 'stad = ___\nprint("Welkom in " + stad)';
const String kSecond = 'naam = ___\nprint(naam)';

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

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  testWidgets('"Continue" pressed in Practice, on a slow Cosmos, brings the '
      'next exercise of the goal in progress', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Vul de stad in.', code: kFirst),
      completeCodeReply(text: 'Geef naam een waarde.', code: kSecond),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'progress': [printDone()],
      },
    );
    await harness.boot(tester);

    // 1. The first "Continue", from the theory view the app opens on:
    //    practice.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == kFirst,
      timeout: const Duration(seconds: 30),
      reason: 'the first exercise never reached the editor',
    );

    // 2. From now on every read of `progress` takes 300 ms.
    harness.cosmos.route(
      'progress',
      _SlowContainer(
        harness.cosmos['progress'].container,
        const Duration(milliseconds: 300),
      ),
    );

    // Back to the learning path and "Continue" again, from Practice.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          editorText(tester) == kSecond ||
          pills(tester).any((p) => p.contains('no goals left')),
      timeout: const Duration(seconds: 30),
      reason: 'neither an exercise nor a pill after "Continue"',
    );
    // Settle whatever is still on its way.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      pills(tester),
      isNot(contains(contains('no goals left'))),
      reason: 'the exercise was asked for before the session had its subgoal',
    );
    expect(editorText(tester), kSecond);
    expect(llm.remaining, 0, reason: 'the second exercise was never asked for');

    harness.cosmos.route('progress', null);
    await harness.dispose(tester);
  });
}
