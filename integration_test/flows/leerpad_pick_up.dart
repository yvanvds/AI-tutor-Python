// End-to-end (#280): on the learning path a student picks a subgoal back
// up from its tile — "Finish" while one of its learning objectives is not
// demonstrated yet, "Review" when all are — practises it, and goes back to
// the goal in progress with "Continue" ("Verder").
//
// Sam finished "Basics" with one learning objective of "Variables" still
// open, and works on "Comparisons" of "Conditions". The teacher decided
// (2026-11-08): a button on the subgoal's tile picks it back up; the open
// learning objectives come first; the student stops with "Continue". The
// oefeningen stay out of the calibration window, nothing is reopened, and
// the turn record says the student chose the subgoal.
//
//   1. The tiles of "Basics" carry "Review" (Print) and "Finish"
//      (Variables), whole inside their tiles, in the runner window and in a
//      700 px one; "Comparisons", the goal in progress, has none.
//   2. "Finish" on "Variables" opens practice on it: the banner says "Your
//      choice", the chat says where the oefeningen are and how to go back.
//      The question is on the open `lo-cast`, prompted under "Basics" —
//      another root goal than the one in progress — and graded in its
//      scope: the answer moves that LO's belief (the bug class of #225 is a
//      stale root that drops it). The record says `selfChosen`; the
//      calibration window stays empty; "Variables" stays finished.
//   3. The learning path keeps "Conditions" as the goal in progress, with
//      its "Continue"; the tile of "Variables" says it is being practised.
//   4. "Continue" goes back to "Comparisons": its answer counts there and
//      enters the calibration window, as any oefening on the goal in
//      progress.
//
// Real app, real navigation, real Leerpad, practice view and editor, real
// TutorService → conductor → question request → grader payload → belief
// math → Cosmos services, with the real font in a narrow window too. Only
// the model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/leerpad_pick_up.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kCastExercise = 'leeftijd = ___(input("Leeftijd? "))';
const String kCastAgain = 'getal = ___("42")\nprint(getal + 1)';
const String kCompareExercise = 'print(3 ___ 5)';
const String kCompareNext = 'print(7 ___ 7)';

Map<String, String> _signal(String subgoalId, String loId, String strength) => {
  'subgoalId': subgoalId,
  'loId': loId,
  'signal': 'positive',
  'strength': strength,
};

/// The turns in the order the app asks for them: the question on the open
/// `lo-cast`, its grade — with a side remark on `lo-var` of the same
/// subgoal, and one on `lo-cmp` of the goal in progress, under another root
/// — the next question on "Variables", then after "Continue" the question
/// on "Comparisons", its grade and the one after it.
List<String> script() => [
  completeCodeReply(text: 'Zet de invoer om.', code: kCastExercise),
  codeFeedbackReply(
    text: 'Juist omgezet.',
    quality: 'correct',
    loSignals: [
      _signal('s2', 'lo-cast', 'strong'),
      _signal('s2', 'lo-var', 'moderate'),
      _signal('s3', 'lo-cmp', 'weak'),
    ],
  ),
  completeCodeReply(text: 'Nog een omzetting.', code: kCastAgain),
  completeCodeReply(text: 'Vergelijk twee getallen.', code: kCompareExercise),
  codeFeedbackReply(
    text: 'Juist vergeleken.',
    quality: 'correct',
    loSignals: [_signal('s3', 'lo-cmp', 'strong')],
  ),
  completeCodeReply(text: 'Nog een vergelijking.', code: kCompareNext),
];

/// "Variables" with a second learning objective, and the goal in progress,
/// "Conditions", with "Comparisons".
List<Map<String, dynamic>> curriculum() => [
  goalDoc(
    id: 's2',
    title: 'Variables',
    parentId: 'r1',
    order: 2000,
    objectives: [
      objective('lo-var', 'Assign a value to a name'),
      objective('lo-cast', 'Turn text into a number'),
    ],
  ),
  goalDoc(id: 'r2', title: 'Conditions', order: 2000),
  goalDoc(
    id: 's3',
    title: 'Comparisons',
    parentId: 'r2',
    order: 1000,
    objectives: [objective('lo-cmp', 'Compare two values')],
  ),
];

final DateTime _finishedAt = DateTime.utc(2026, 10, 20, 10);

/// The student was moved past [goalId] at [_finishedAt].
Map<String, dynamic> advancedPast(String goalId, double progress) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': progress,
  'updatedAt': _finishedAt.toIso8601String(),
  'lastSessionAt': _finishedAt.toIso8601String(),
  'advancedAt': _finishedAt.toIso8601String(),
};

/// A belief doc last asked directly three days ago; [stamped] with the
/// stamp of formula 1.1 on two right own questions.
Map<String, dynamic> belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  bool stamped = false,
}) {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 3));
  return {
    'id': '${kStudentUid}_${subgoalId}_$loId',
    'type': 'lo_belief',
    'uid': kStudentUid,
    'subgoalId': subgoalId,
    'loId': loId,
    'alpha': alpha,
    'beta': beta,
    'lastUpdatedAt': at.toIso8601String(),
    'lastProbedAt': at.toIso8601String(),
    'lastQuestionType': 'completeCodeQuestion',
    'recentNegativesAtCalibrated': 0,
    'ownQuestions': 3,
    'ownQuestionsRight': stamped ? 2 : 1,
    'ownQuestionsRightNonMcq': stamped ? 2 : 1,
    if (stamped) ...{
      'firstMasteredAt': at.toIso8601String(),
      'lastPositiveAtCalibratedAt': at.toIso8601String(),
      'highestPositiveDifficulty': 'medium',
    },
  };
}

/// One instruction doc whose text names the goal, the subgoal and the
/// grading scope, so the flow can read what the model was told.
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
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  Finder card(String rootId) =>
      find.byWidgetPredicate((w) => w is LeerpadCard && w.root.id == rootId);
  Finder inCard(String rootId, Finder what) =>
      find.descendant(of: card(rootId), matching: what);
  Finder chip(String goalId) => find.byWidgetPredicate(
    (w) => w is LeerpadChildChip && w.goal.id == goalId,
  );
  Finder pickUp(String goalId) =>
      find.byKey(ValueKey('leerpad-pick-up-$goalId'));
  Finder inBanner(String text) => find.descendant(
    of: find.byType(ObjectiveBanner),
    matching: find.text(text),
  );

  bool inside(Rect outer, Rect inner) =>
      inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;

  Rect window(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  /// Each pick-up button whole inside its tile and inside the window.
  void buttonsInReach(WidgetTester tester, List<String> ids, String where) {
    for (final id in ids) {
      final rect = tester.getRect(pickUp(id));
      expect(inside(tester.getRect(chip(id)), rect), isTrue, reason: where);
      expect(inside(window(tester), rect), isTrue, reason: '$where: $id');
    }
  }

  Future<void> waitForExercise(WidgetTester tester, String code) => pumpUntil(
    tester,
    () => editorText(tester) == code,
    timeout: const Duration(seconds: 30),
    reason: 'the exercise never reached the editor:\n$code',
  );

  /// The notice of a badge the first answer earned lies over the run
  /// controls in a 700 px window (#283): a student closes it before handing
  /// the next answer in.
  Future<void> closeBadgeToasts(WidgetTester tester) async {
    final toast = find.byKey(const ValueKey('badge-toast'));
    while (toast.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: toast, matching: find.byTooltip('Close')),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// Hands the code in with "Send to tutor".
  Future<void> send(WidgetTester tester) async {
    await closeBadgeToasts(tester);
    await tester.tap(find.byTooltip('Send to tutor'));
  }

  Future<void> openLearningPath(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, card('r2'));
  }

  Map<String, dynamic> jsonAt(AppHarness harness, int i) =>
      jsonDecode(harness.llm!.sentInputs[i]) as Map<String, dynamic>;

  Iterable<String> keysOf(Map<String, dynamic> request, String field) =>
      (request[field] as List).cast<Map>().map(
        (lo) => '${lo['subgoalId']}/${lo['id']}',
      );

  Iterable<String> idsOf(Map<String, dynamic> request, String field) =>
      (request[field] as List).cast<Map>().map((lo) => '${lo['id']}');

  List<dynamic> calibrationWindow(AppHarness harness) =>
      ((harness.cosmos['accounts'].docs[kStudentUid]!['calibration']
              as Map)['recentAnswers']
          as List?) ??
      const [];

  testWidgets('"Finish" on a subgoal of a finished goal: its open LO first, '
      'graded under that goal so the answer counts, out of the calibration '
      'window and without reopening it; "Continue" goes back to the goal in '
      'progress, in a narrow window too', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'goals': curriculum(),
        'progress': [advancedPast('s1', 1.0), advancedPast('s2', 0.5)],
        'lo_beliefs': [
          belief('s1', 'lo-print', alpha: 5, beta: 1, stamped: true),
          belief('s2', 'lo-var', alpha: 5, beta: 1, stamped: true),
          belief('s2', 'lo-cast', alpha: 3, beta: 2),
        ],
        'instructions': [scopeInstruction()],
      },
    );
    await harness.boot(tester);

    // 1. The finished goal's tiles carry the buttons; the goal in
    //    progress keeps "Continue" and its tile none.
    await openLearningPath(tester);
    await pumpUntilFound(tester, pickUp('s2'));
    expect(inCard('r2', find.text('Continue')), findsOneWidget);
    expect(inCard('r1', find.text('Continue')), findsNothing);
    expect(
      find.descendant(of: pickUp('s1'), matching: find.text('Review')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pickUp('s2'), matching: find.text('Finish')),
      findsOneWidget,
    );
    expect(pickUp('s3'), findsNothing);
    buttonsInReach(tester, ['s1', 's2'], 'runner window');

    tester.view.physicalSize =
        Size(700, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
    await pumpUntil(
      tester,
      () => tester.getSize(card('r1')).width < 760,
      reason: 'the card never narrowed with the window',
    );
    buttonsInReach(tester, ['s1', 's2'], '700 px');

    // 2. "Finish" on "Variables": practice on it, said so.
    await tester.tap(pickUp('s2'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, kCastExercise);
    expect(inBanner('YOUR CHOICE'), findsOneWidget);
    expect(inBanner('Variables'), findsOneWidget);
    expect(inBanner('CURRENT GOAL'), findsNothing);
    expect(
      pills(tester),
      contains(
        'You picked Variables: the exercises are on it now. Done? Continue '
        'in the learning path takes you back to your current goal.',
      ),
    );
    expect(pills(tester), isNot(contains(contains('check question'))));

    // Asked on the open LO, under "Basics".
    final asked = jsonAt(harness, 0);
    // A question request names its LO; the grading names the subgoal too.
    expect(idsOf(asked, 'target_los'), ['lo-cast']);
    expect(
      harness.llm!.sentInstructions[0],
      contains('Goal: Basics. Subgoal: Variables.'),
    );

    await send(tester);
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == 1,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded for the answer on "Variables"',
    );
    await waitForExercise(tester, kCastAgain);
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle',
    );

    // Graded in the scope of "Basics": the target and the side remark on
    // the same subgoal count; the remark on the goal in progress, under
    // another root, does not.
    final grading = jsonAt(harness, 1);
    expect(grading['request_type'], 'submit_code');
    expect(keysOf(grading, 'target_los'), ['s2/lo-cast']);
    expect(
      keysOf(grading, 'goal_scope_los'),
      unorderedEquals(['s1/lo-print', 's2/lo-var', 's2/lo-cast']),
    );
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalId'], 's2');
    expect(turn['targetLOIds'], ['lo-cast']);
    expect(turn['selfChosen'], isTrue);
    expect(turn.containsKey('activeSubgoalId'), isFalse);
    expect(turn['hadFallback'], isFalse);
    expect(turn['subgoalAdvanced'], isFalse);
    expect(
      (turn['appliedSignals'] as List).cast<Map>().map(
        (a) => '${a['subgoalId']}/${a['loId']}',
      ),
      ['s2/lo-cast', 's2/lo-var'],
    );
    expect(turn.containsKey('signalEvents'), isFalse);
    final cast =
        harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s2_lo-cast']!;
    expect(cast['alpha'] as num, greaterThan(3));
    expect(cast['ownQuestions'], 4);
    expect(cast['ownQuestionsRight'], 2);
    expect(
      harness.cosmos['lo_beliefs'].docs.containsKey('${kStudentUid}_s3_lo-cmp'),
      isFalse,
    );
    // Out of the calibration window, and "Variables" stays finished.
    expect(turn['calibrationBefore'], 'medium');
    expect(turn['calibrationAfter'], 'medium');
    expect(calibrationWindow(harness), isEmpty);
    final variables = harness.cosmos['progress'].docs['${kStudentUid}_s2']!;
    expect(variables['advancedAt'], _finishedAt.toIso8601String());
    // The question after it is on "Variables" too: nothing interrupted.
    expect(idsOf(jsonAt(harness, 2), 'target_los'), ['lo-cast']);

    // 3. The learning path: "Conditions" is still the goal in progress.
    await openLearningPath(tester);
    await pumpUntilFound(tester, find.text('practising now'));
    expect(
      find.descendant(of: chip('s2'), matching: find.text('practising now')),
      findsOneWidget,
    );
    expect(pickUp('s2'), findsNothing);
    expect(pickUp('s1'), findsOneWidget);
    expect(inCard('r2', find.text('Continue')), findsOneWidget);
    expect(inCard('r1', find.text('Continue')), findsNothing);
    expect(inCard('r1', find.text('completed')), findsOneWidget);

    // 4. "Continue": back on "Comparisons", where the answer counts and
    //    calibrates.
    await tester.tap(inCard('r2', find.text('Continue')));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, kCompareExercise);
    await pumpUntilFound(tester, inBanner('CURRENT GOAL'));
    expect(inBanner('Comparisons'), findsOneWidget);
    expect(inBanner('YOUR CHOICE'), findsNothing);
    expect(idsOf(jsonAt(harness, 3), 'target_los'), ['lo-cmp']);
    expect(
      harness.llm!.sentInstructions[3],
      contains('Goal: Conditions. Subgoal: Comparisons.'),
    );

    await send(tester);
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.length == 2,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded for the answer on "Comparisons"',
    );
    await waitForExercise(tester, kCompareNext);
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle',
    );
    expect(harness.llm!.remaining, 0);

    expect(keysOf(jsonAt(harness, 4), 'goal_scope_los'), ['s3/lo-cmp']);
    final back = harness.cosmos['turn_history'].docs.values.singleWhere(
      (t) => t['subgoalId'] == 's3',
    );
    expect(back.containsKey('selfChosen'), isFalse);
    expect(
      (back['appliedSignals'] as List).cast<Map>().single['loId'],
      'lo-cmp',
    );
    final cmp = harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s3_lo-cmp'];
    expect(cmp, isNotNull);
    expect(cmp!['alpha'], closeTo(3.0, 1e-9));
    expect(calibrationWindow(harness), hasLength(1));
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s2']!['advancedAt'],
      _finishedAt.toIso8601String(),
    );

    await harness.dispose(tester);
  });
}
