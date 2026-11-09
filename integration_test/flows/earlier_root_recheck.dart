// End-to-end (#275, formula 1.1): what the recheck slot brings back now —
// an open core LO of an earlier root goal, a stuck LO a notch lower first,
// and a thin stamp from before 1.1 — and what follows the answer.
//
// Until #275 a recheck only asked an LO of an earlier subgoal of the root
// the student was on, and only just under the bar (μ 0.70–0.80). Once a
// student moved on to the next root goal, nothing of the old one came back;
// a stuck LO, at μ < 0.6, never did; and a stamp from before 1.1 that fell
// on one right own question was never looked at again. The teacher decided
// (2026-11-08): open core LOs of a milestone come back, also of earlier
// root goals, the milestone still open first; stuck LOs come back a level
// lower first; a thin stamp gets one check after a week and keeps its
// stamp. A right answer brings the next question on that LO in the same
// session; a wrong one brings the LO back at the next session.
//
//   1. "Old topic" lies under the earlier root "Earlier". Its `lo-old` is
//      core in a milestone due in ten days, at μ 0.5 and not asked for ten
//      days; the student is on "Variables" of "Basics". The first exercise
//      is a check question on "Old topic", announced in chat; the model is
//      prompted under "Earlier", and the grader gets "Old topic" in its
//      scope, so the right answer lands on the old LO as a direct probe.
//      It is not mastered yet, so the next exercise is on it again,
//      announced as such; a wrong answer there ends the run, marks the LO
//      for the next session, and practice goes on.
//   2. `lo-print` of "Print" is stuck (six own questions, μ 0.29). It comes
//      back on easy, a level under the student's medium — the chip in the
//      top bar says so — and after a right answer the next question on it
//      is on medium.
//   3. `lo-print` carries a stamp from before 1.1 on one right own
//      question. One check question; a wrong answer leaves the stamp, and
//      no question follows.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → question request → grader payload → belief
// math → Cosmos services. Only the model is scripted (`ScriptedLlm`, raw
// assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/earlier_root_recheck.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kCheckExercise = 'oud = ___';
const String kAgainExercise = 'oud = ___\nprint(oud)';
const String kVariablesExercise = 'stad = ___\nprint("Welkom in " + stad)';

Map<String, String> _signal(String subgoalId, String loId, String signal) => {
  'subgoalId': subgoalId,
  'loId': loId,
  'signal': signal,
  'strength': 'strong',
};

/// A check question, its grade, the next one and its grade, then the
/// active subgoal's exercise: the run of a returned LO, right then wrong.
List<String> runScript({required String subgoalId, required String loId}) => [
  completeCodeReply(
    text: 'Tussendoor: geef oud een waarde.',
    code: kCheckExercise,
  ),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: [_signal(subgoalId, loId, 'positive')],
  ),
  completeCodeReply(text: 'Nog een: toon oud ook.', code: kAgainExercise),
  codeFeedbackReply(
    text: 'Nog niet: kijk naar de naam.',
    quality: 'wrong',
    loSignals: [_signal(subgoalId, loId, 'negative')],
  ),
  completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
];

/// The student moved past [goalId]: finished, its LOs not all stamped.
Map<String, dynamic> advancedPast(String goalId, DateTime at) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': 0.0,
  'updatedAt': at.toIso8601String(),
  'lastSessionAt': at.toIso8601String(),
  'advancedAt': at.toIso8601String(),
};

/// A belief doc on [subgoalId]/[loId], last asked directly [probedAt].
Map<String, dynamic> beliefDoc(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  required int own,
  required int right,
  required DateTime probedAt,
  DateTime? stampedAt,
}) => {
  'id': '${kStudentUid}_${subgoalId}_$loId',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': subgoalId,
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': probedAt.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'recentNegativesAtCalibrated': 0,
  'lastProbedAt': probedAt.toIso8601String(),
  'ownQuestions': own,
  'ownQuestionsRight': right,
  'ownQuestionsRightNonMcq': right,
  if (stampedAt != null) ...{
    'firstMasteredAt': stampedAt.toIso8601String(),
    'lastPositiveAtCalibratedAt': stampedAt.toIso8601String(),
    'highestPositiveDifficulty': 'medium',
  },
};

/// The seeded account with a full calibration window at medium, all right:
/// the brake on recent work lets a recheck through.
Map<String, dynamic> accountWithGoodWindow() {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return {
    ...accountDoc(studentIdentity),
    'calibration': {
      'difficulty': 'medium',
      'recentAnswers': [
        for (var i = 0; i < PolicyConstants.calibrationWindow; i++)
          {
            'quality': 'correct',
            'difficulty': 'medium',
            'at': at.toIso8601String(),
          },
      ],
      'recentQuestionTypes': const <String>[],
    },
  };
}

/// One instruction doc whose text names the goal, the subgoal and the
/// grading scope, so a flow can read what the model was told.
Map<String, dynamic> scopeInstruction() => {
  'id': 'alwaysInclude',
  'type': 'instruction',
  'sections': {
    'context': 'Goal: {goal}. Subgoal: {subgoal}.\nScope:\n{goalScopeLOs}',
  },
  'updatedAt': '2026-05-01T10:00:00Z',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  final chip = find.descendant(
    of: find.byType(StatStrip),
    matching: find.byType(DifficultyChip),
  );

  /// The chip in the top bar says [level] for this exercise; [lower]: a
  /// level lower for this learning objective, as a notch drop says.
  Future<void> expectChip(
    WidgetTester tester,
    String level, {
    bool lower = false,
  }) async {
    final tooltip = lower
        ? 'This exercise: $level, one level lower for this learning objective'
        : 'This exercise: $level';
    await pumpUntil(
      tester,
      () =>
          find
              .descendant(of: chip, matching: find.text(level))
              .evaluate()
              .isNotEmpty &&
          find.byTooltip(tooltip).evaluate().isNotEmpty,
      reason: 'the chip never said "$level" / "$tooltip"',
    );
  }

  Future<void> waitForExercise(WidgetTester tester, String code) => pumpUntil(
    tester,
    () => editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise never reached the editor:\n$code',
  );

  /// Boots onto "Variables" (no lesson content, so the leerpad opens the
  /// practice editor directly) and waits for the first exercise.
  Future<void> openPractice(
    WidgetTester tester,
    AppHarness harness, {
    required String firstExercise,
  }) async {
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, firstExercise);
  }

  /// Hands the code in and waits until [turns] oefeningen are recorded and
  /// [next] is in the editor.
  Future<void> submit(
    WidgetTester tester,
    AppHarness harness, {
    required int turns,
    required String next,
  }) async {
    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == turns,
      timeout: const Duration(seconds: 30),
      reason: 'oefening $turns was not recorded',
    );
    await waitForExercise(tester, next);
  }

  List<Map<String, dynamic>> turnsOf(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.toList()..sort(
        (a, b) => (a['turnAt'] as String).compareTo(b['turnAt'] as String),
      );

  Map<String, dynamic> jsonAt(AppHarness harness, int i) =>
      jsonDecode(harness.llm!.sentInputs[i]) as Map<String, dynamic>;

  final now = DateTime.now().toUtc();
  final tenDaysAgo = now.subtract(const Duration(days: 10));

  testWidgets('an open core LO of an earlier root goal comes back: announced, '
      'prompted and graded under that goal; right brings one more question '
      'on it, wrong ends the run until the next session', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(runScript(subgoalId: 'e0', loId: 'lo-old')),
      extraDocs: {
        'accounts': [accountWithGoodWindow()],
        'goals': [
          goalDoc(id: 'r0', title: 'Earlier', order: 0),
          goalDoc(
            id: 'e0',
            title: 'Old topic',
            parentId: 'r0',
            order: 1000,
            objectives: [objective('lo-old', 'Give a name a value')],
          ),
        ],
        'progress': [
          advancedPast('e0', tenDaysAgo),
          advancedPast('s1', tenDaysAgo),
        ],
        'milestones': [
          {
            'id': 'm-earlier',
            'type': 'milestone',
            'title': 'Earlier',
            'periodStart': now
                .subtract(const Duration(days: 60))
                .toIso8601String(),
            'dueAt': now.add(const Duration(days: 10)).toIso8601String(),
            'expectedDifficulty': 'medium',
            'subgoalIds': ['e0'],
            'coreLoKeys': ['e0/lo-old'],
          },
        ],
        'lo_beliefs': [
          beliefDoc(
            'e0',
            'lo-old',
            alpha: 3,
            beta: 3,
            own: 3,
            right: 1,
            probedAt: tenDaysAgo,
          ),
        ],
        'instructions': [scopeInstruction()],
      },
    );
    await openPractice(tester, harness, firstExercise: kCheckExercise);

    // The student sees why this question is about an older topic.
    expect(
      pills(tester),
      contains(contains('one check question on Old topic')),
    );

    // Asked under the earlier goal, with that subgoal in the scope.
    final asked = jsonAt(harness, 0);
    expect(asked['request_type'], 'complete_code');
    expect(asked['difficulty'], 'medium');
    expect((asked['target_los'] as List).cast<Map>().single['id'], 'lo-old');
    expect(
      harness.llm!.sentInstructions[0],
      contains('Goal: Earlier. Subgoal: Old topic.'),
    );
    expect(harness.llm!.sentInstructions[0], contains('[e0] (apply) lo-old'));

    await submit(tester, harness, turns: 1, next: kAgainExercise);

    // The grader was told the target lives in "Old topic", and that subgoal
    // is in its scope next to the active root's.
    final grading = jsonAt(harness, 1);
    final target = (grading['target_los'] as List).cast<Map>().single;
    expect((target['id'], target['subgoalId']), ('lo-old', 'e0'));
    final scope = (grading['goal_scope_los'] as List).cast<Map>();
    expect(scope.map((e) => e['subgoalId']), containsAll(['s1', 's2', 'e0']));

    // A direct probe of the old LO, recorded as a recheck that came back
    // because it is an open core LO.
    final first = turnsOf(harness).single;
    expect(first['isRecheck'], isTrue);
    expect(first['recheckRule'], 'open');
    expect(first['subgoalId'], 'e0');
    expect(first['activeSubgoalId'], 's2');
    expect(
      (first['appliedSignals'] as List).cast<Map>().single['subgoalId'],
      'e0',
    );
    var old = harness.cosmos['lo_beliefs'].docs['${kStudentUid}_e0_lo-old']!;
    expect(old['ownQuestions'], 4);
    expect(old['ownQuestionsRight'], 2);
    expect(old['lastProbedAt'], old['lastUpdatedAt']);
    expect(old.containsKey('firstMasteredAt'), isFalse);

    // Right and not mastered: the next question is on it again, said so.
    expect(
      pills(tester),
      contains(
        'One more check question on Old topic: you got the last one right.',
      ),
    );
    final again = jsonAt(harness, 2);
    expect(again['request_type'], 'write_code');
    expect((again['target_los'] as List).cast<Map>().single['id'], 'lo-old');

    await submit(tester, harness, turns: 2, next: kVariablesExercise);

    final second = turnsOf(harness).last;
    expect(second['isRecheck'], isTrue);
    expect(second['recheckRule'], 'open');
    expect(
      (second['selectionReason'] as Map)['chosenReason'],
      contains('again after a right answer'),
    );
    // Wrong: back at the next session, not after a week.
    old = harness.cosmos['lo_beliefs'].docs['${kStudentUid}_e0_lo-old']!;
    expect(old['returnWrongAt'], old['lastUpdatedAt']);
    expect(old['ownQuestions'], 5);
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });

  testWidgets('a stuck LO comes back a level lower first — the chip says '
      'easy — and the question after a right answer is on the student\'s '
      'level', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(runScript(subgoalId: 's1', loId: 'lo-print')),
      extraDocs: {
        'accounts': [accountWithGoodWindow()],
        'progress': [advancedPast('s1', tenDaysAgo)],
        'lo_beliefs': [
          beliefDoc(
            's1',
            'lo-print',
            alpha: 2,
            beta: 5,
            own: 6,
            right: 0,
            probedAt: tenDaysAgo,
          ),
        ],
      },
    );
    await openPractice(tester, harness, firstExercise: kCheckExercise);

    expect(pills(tester), contains(contains('one check question on Print')));
    expect(jsonAt(harness, 0)['difficulty'], 'easy');
    await expectChip(tester, 'easy', lower: true);

    await submit(tester, harness, turns: 1, next: kAgainExercise);
    final first = turnsOf(harness).single;
    expect(first['recheckRule'], 'stuck');
    expect(first['difficulty'], 'easy');
    expect(first['calibrationBefore'], 'medium');
    final reason = first['selectionReason'] as Map;
    expect(reason['notchDropFired'], isTrue);
    expect(reason['notchDropRules'], ['stuckReturn']);
    // The lower level is no positive at the student's level.
    final print =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print']!;
    expect(print.containsKey('lastPositiveAtCalibratedAt'), isFalse);
    expect(print['highestPositiveDifficulty'], 'easy');

    expect(jsonAt(harness, 2)['difficulty'], 'medium');
    await expectChip(tester, 'medium');
    await submit(tester, harness, turns: 2, next: kVariablesExercise);
    final second = turnsOf(harness).last;
    expect(second['difficulty'], 'medium');
    expect((second['selectionReason'] as Map)['notchDropFired'], isFalse);
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });

  testWidgets('a thin stamp from before 1.1 gets one check question; a wrong '
      'answer leaves the stamp, and no question follows', (tester) async {
    final stampedAt = now.subtract(const Duration(days: 20));
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(
          text: 'Tussendoor: toon een tekst.',
          code: kCheckExercise,
        ),
        codeFeedbackReply(
          text: 'Nog niet.',
          quality: 'wrong',
          loSignals: [_signal('s1', 'lo-print', 'negative')],
        ),
        completeCodeReply(text: 'Vul de stad in.', code: kVariablesExercise),
      ]),
      extraDocs: {
        'accounts': [accountWithGoodWindow()],
        'progress': [advancedPast('s1', tenDaysAgo)],
        'lo_beliefs': [
          beliefDoc(
            's1',
            'lo-print',
            alpha: 5,
            beta: 1,
            own: 2,
            right: 1,
            probedAt: tenDaysAgo,
            stampedAt: stampedAt,
          ),
        ],
      },
    );
    await openPractice(tester, harness, firstExercise: kCheckExercise);
    expect(pills(tester), contains(contains('one check question on Print')));

    await submit(tester, harness, turns: 1, next: kVariablesExercise);

    final turn = turnsOf(harness).single;
    expect(turn['recheckRule'], 'thin');
    expect(turn['difficulty'], 'medium');
    final print =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print']!;
    expect(print['firstMasteredAt'], stampedAt.toIso8601String());
    expect(print['thinCheckedAt'], print['lastUpdatedAt']);
    expect(print.containsKey('returnWrongAt'), isFalse);
    expect(pills(tester), isNot(contains(contains('One more check question'))));
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });
}
