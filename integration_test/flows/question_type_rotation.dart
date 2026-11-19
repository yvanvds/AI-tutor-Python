// End-to-end (#312): the question type rotates per learning objective, on
// the type that LO got the last time — whatever was asked in between.
//
// The teacher practised a whole subgoal and only ever got "complete the
// code" and "explain the code"; in the class 4 of 741 own questions asked
// the student to write a script. CONDUCTOR_POLICY §2.2 lets an `apply` LO
// alternate between `completeCode` and `writeCode`, but the conductor read
// "the previous type on this LO" from the question before this one, and the
// recency guard (§2.1) nearly never asks an LO twice in a row. So nothing
// was excluded and every `apply` LO got `completeCode`, every time.
//
// "Variables" has two `apply` LOs, both open. `lo-var` has evidence from the
// side only (no question of its own yet); `lo-cast` was last asked as a
// "write the code" question in an earlier session.
//
//   1. `lo-var`, the weakest: complete the code — no previous type.
//   2. `lo-cast`: complete the code — its last one was write the code, in
//      another session.
//   3. `lo-var` again: write the code — it got complete the code two
//      questions ago. The student gets the assignment in chat and an editor
//      without gaps to fill.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → question request → grader payload → Cosmos.
// Only the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/question_type_rotation.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kVarExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kCastExercise = 'getal = ___(input("Getal: "))\nprint(getal + 1)';
const String kWriteAssignment =
    'Schrijf een programma dat je naam in een variabele bewaart en toont.';

/// A wrong answer on [loId]: the LO stays open and the next question comes.
String wrongOn(String loId) => codeFeedbackReply(
  text: 'Nog niet helemaal.',
  quality: 'wrong',
  loSignals: [
    {
      'subgoalId': 's2',
      'loId': loId,
      'signal': 'negative',
      'strength': 'strong',
    },
  ],
);

/// "Print" is done.
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'advancedAt': '2026-08-03T10:00:00Z',
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// "Variables" with two `apply` LOs.
List<Map<String, dynamic>> curriculum() => [
  goalDoc(
    id: 's2',
    title: 'Variables',
    parentId: 'r1',
    order: 2000,
    objectives: [
      objective('lo-var', 'Assign a value to a name'),
      objective('lo-cast', 'Convert text input to a number'),
    ],
  ),
];

/// An open LO of "Variables" at ([alpha], [beta]), last asked as
/// [lastQuestionType] — absent for a doc that only got signals from the
/// side.
Map<String, dynamic> openDoc(
  String loId,
  double alpha,
  double beta,
  DateTime at, {
  String? lastQuestionType,
}) => {
  'id': '${kStudentUid}_s2_$loId',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': at.toIso8601String(),
  if (lastQuestionType != null) 'lastQuestionType': lastQuestionType,
  'recentNegativesAtCalibrated': 0,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Future<void> waitForExercise(WidgetTester tester, String code) => pumpUntil(
    tester,
    () => editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise never reached the editor:\n$code',
  );

  Future<void> waitForTurns(
    WidgetTester tester,
    AppHarness harness,
    int turns,
  ) => pumpUntil(
    tester,
    () => harness.cosmos['turn_history'].docs.length == turns,
    timeout: const Duration(seconds: 30),
    reason: 'oefening $turns was not recorded',
  );

  List<Map<String, dynamic>> turnsOf(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList()..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );

  Map<String, dynamic> jsonAt(AppHarness harness, int i) =>
      jsonDecode(harness.llm!.sentInputs[i]) as Map<String, dynamic>;

  String targetOf(Map<String, dynamic> request) =>
      (request['target_los'] as List).cast<Map>().single['id'] as String;

  Map<String, dynamic> belief(AppHarness harness, String loId) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s2_$loId']!;

  testWidgets('an apply LO that got "complete the code" gets "write the code" '
      'the next time, also with another LO asked in between', (tester) async {
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Vul de stad in.', code: kVarExercise),
        wrongOn('lo-var'),
        completeCodeReply(text: 'Zet de invoer om.', code: kCastExercise),
        wrongOn('lo-cast'),
        llmEnvelope(text: kWriteAssignment, meta: '{"type":"write_code"}'),
      ]),
      extraDocs: {
        'goals': curriculum(),
        'progress': [printDone()],
        'lo_beliefs': [
          // μ 0.44, the weakest: asked first. Never the target of a question.
          openDoc('lo-var', 2, 2.5, yesterday),
          // μ 0.5, last asked as a "write the code" question.
          openDoc(
            'lo-cast',
            3,
            3,
            yesterday,
            lastQuestionType: 'writeCodeQuestion',
          ),
        ],
      },
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    // 1. `lo-var`, no previous type: complete the code.
    await waitForExercise(tester, kVarExercise);
    final first = jsonAt(harness, 0);
    expect(targetOf(first), 'lo-var');
    expect(first['request_type'], 'complete_code');

    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 1);

    // 2. `lo-cast`, last asked as write the code: complete the code.
    await waitForExercise(tester, kCastExercise);
    final second = jsonAt(harness, 2);
    expect(targetOf(second), 'lo-cast');
    expect(second['request_type'], 'complete_code');
    // The doc of `lo-var` remembers what it got.
    expect(
      belief(harness, 'lo-var')['lastQuestionType'],
      'completeCodeQuestion',
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForTurns(tester, harness, 2);

    // 3. `lo-var` again, with `lo-cast` asked in between: write the code.
    await pumpUntil(
      tester,
      () => harness.llm!.remaining == 0,
      timeout: const Duration(seconds: 30),
      reason: 'the third exercise was never asked',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle after the third exercise',
    );
    final third = jsonAt(harness, 4);
    expect(targetOf(third), 'lo-var');
    expect(third['request_type'], 'write_code');

    // The student has the assignment in chat and an editor with no gap to
    // fill: the script is theirs to write.
    await pumpUntilFound(
      tester,
      find.textContaining(kWriteAssignment, findRichText: true),
    );
    expect(editorText(tester), isNot(contains('___')));
    expect(editorText(tester), isNot(kCastExercise));

    final turns = turnsOf(harness);
    expect(turns.map((t) => t['questionType']), [
      'completeCodeQuestion',
      'completeCodeQuestion',
    ]);
    expect(turns.map((t) => t['targetLOIds']), [
      ['lo-var'],
      ['lo-cast'],
    ]);
    expect(turns.every((t) => t['subgoalAdvanced'] == false), isTrue);
    expect(
      belief(harness, 'lo-cast')['lastQuestionType'],
      'completeCodeQuestion',
    );

    await harness.dispose(tester);
  });
}
