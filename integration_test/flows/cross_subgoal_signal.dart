// End-to-end (#108, #167): a mistake in later work that points to a gap in
// an earlier subgoal reaches that earlier LO — as a prompt, not as
// evidence. The student mastered "Print" three weeks ago and is now on
// "Variables"; the grader marks the answer wrong with a negative on the
// target *and* a negative on `s1/lo-print` (the contract's cross-subgoal
// `loSignals`). Since #167 the app writes nothing to the old belief for
// that negative: (α, β) and the decay clock stay exactly as they were, and
// the doc is only flagged `regressedAt` (#112). The `turn_history` doc
// names both grader signals, applies only the target's, and lists
// `lo-print` under `reviewFlags`. The student's next session then opens
// with the warm-up review on "Print" (#102) although the LO is nowhere near
// stale, and answering it is the direct measurement that counts: full
// weight, flag cleared. An LO never probed before gets neither a doc nor a
// flag: there is nothing to review, and a never-asked LO must not start
// life in debit.
//
// Before #167 the same negative debited the belief (decayed β plus the
// weight as medium, clock reset), and it was that debit — never re-tested,
// because the tutor no longer probes a finished subgoal — that erased
// demonstrated mastery from everything the belief steers.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → belief math → Cosmos
// services. Only the model is scripted (`ScriptedLlm`, raw assistant text
// through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/cross_subgoal_signal.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'stad = ___\nprint("Welkom in " + stad)';
const String kNextExercise = 'leeftijd = ___\nprint(leeftijd)';
const String kWarmUpExercise = 'print(___)';

/// The exercise for the active subgoal, a wrong grade that blames the
/// target and the earlier `print()` LO, and the exercise the app asks for
/// next.
List<String> script() => [
  completeCodeReply(text: 'Vul de stad in.', code: kExercise),
  codeFeedbackReply(
    text: 'De variabele klopt niet, en print() mist zijn haakjes.',
    quality: 'wrong',
    loSignals: const [
      {
        'subgoalId': 's2',
        'loId': 'lo-var',
        'signal': 'negative',
        'strength': 'strong',
      },
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'moderate',
      },
    ],
  ),
  completeCodeReply(text: 'Nu de leeftijd.', code: kNextExercise),
];

/// The next session: the review question on `lo-print` the flag asked
/// for, answered correctly, then the active subgoal's exercise.
List<String> reviewScript() => [
  completeCodeReply(
    text: 'Even opwarmen: toon een tekst.',
    code: kWarmUpExercise,
  ),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  ),
  completeCodeReply(text: 'Vul de stad in.', code: kExercise),
];

/// "Print" is done: its progress is cached at 1.0, so the conductor lands
/// the student on "Variables".
Map<String, dynamic> printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'updatedAt': '2026-08-03T10:00:00Z',
  'lastSessionAt': '2026-08-03T10:00:00Z',
};

/// The belief on `lo-print` as it was written three weeks ago.
Map<String, dynamic> printBelief({required DateTime lastUpdatedAt}) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 5.0,
  'beta': 1.0,
  'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': lastUpdatedAt.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  'firstMasteredAt': lastUpdatedAt.toIso8601String(),
};

/// The seeded account, calibrated at `hard` so the probe is asked at hard
/// and the target's own debit (× 1.4) is observable next to the untouched
/// earlier LO.
Map<String, dynamic> hardStudent() => {
  ...accountDoc(studentIdentity),
  'calibration': {
    'difficulty': 'hard',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  /// Boots onto "Variables" (no lesson content, so the leerpad opens the
  /// practice editor directly) and waits for [firstExercise] to reach the
  /// editor.
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
    await pumpUntil(
      tester,
      () => editorText(tester) == firstExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
  }

  /// Sends the editor's code to the tutor and waits for the grade to be
  /// integrated and [nextExercise] to arrive.
  Future<void> sendAndWait(
    WidgetTester tester,
    AppHarness harness, {
    required String nextExercise,
  }) async {
    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => harness.cosmos['turn_history'].docs.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no turn was recorded after the code was sent',
    );
    await pumpUntil(
      tester,
      () => editorText(tester) == nextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
  }

  Future<void> answerOnce(WidgetTester tester, AppHarness harness) async {
    await openPractice(tester, harness, firstExercise: kExercise);
    await sendAndWait(tester, harness, nextExercise: kNextExercise);
  }

  Map<String, dynamic> turn(AppHarness harness) =>
      harness.cosmos['turn_history'].docs.values.single;

  Map<String, dynamic>? storedPrint(AppHarness harness) =>
      harness.cosmos['lo_beliefs'].docs['${kStudentUid}_s1_lo-print'];

  // Three weeks: old enough that decay would be visible had it been
  // persisted, recent enough that the LO is not due for a warm-up review
  // on staleness (#102, `warmUpStaleAfter`) — so the review in the second
  // session can only come from the flag.
  final weeksAgo = DateTime.now().toUtc().subtract(
    PolicyConstants.warmUpStaleAfter - const Duration(days: 9),
  );

  testWidgets('a wrong answer on a later subgoal that blames an earlier LO '
      'leaves that LO\'s belief untouched and flags it; the next session '
      'opens with its review, and that direct probe is what counts', (
    tester,
  ) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'accounts': [hardStudent()],
        'progress': [printDone()],
        'lo_beliefs': [printBelief(lastUpdatedAt: weeksAgo)],
      },
    );
    await answerOnce(tester, harness);

    final t = turn(harness);
    expect(t['subgoalId'], 's2');
    expect(t['difficulty'], 'hard');
    // Both grader signals are on record, with their subgoal.
    final signalled = (t['loSignals'] as List).cast<Map>();
    expect(
      signalled.map((s) => s['loId']),
      containsAll(['lo-var', 'lo-print']),
    );
    expect(
      signalled.singleWhere((s) => s['loId'] == 'lo-print')['subgoalId'],
      's1',
    );
    // Only the target's was applied: a strong negative at hard.
    final applied = (t['appliedSignals'] as List).cast<Map>();
    final onTarget = applied.single;
    expect(onTarget['loId'], 'lo-var');
    expect(onTarget['subgoalId'], 's2');
    expect(onTarget['betaDelta'], closeTo(2.0 * 1.4, 1e-9));
    // The earlier LO's negative became a review flag instead.
    expect(t['reviewFlags'], [
      {'subgoalId': 's1', 'loId': 'lo-print'},
    ]);

    final print = storedPrint(harness)!;
    // Nothing on the belief moved: (5, 1) as written three weeks ago, the
    // clock included — no decay persisted, no debit, no reset.
    expect(print['alpha'], 5.0);
    expect(print['beta'], 1.0);
    expect(print['lastUpdatedAt'], weeksAgo.toIso8601String());
    expect(print['highestPositiveDifficulty'], 'medium');
    expect(print['lastPositiveAtCalibratedAt'], weeksAgo.toIso8601String());
    expect(print['firstMasteredAt'], weeksAgo.toIso8601String());
    expect(print['recentNegativesAtCalibrated'], 0);
    expect(print['lastQuestionType'], 'completeCodeQuestion');
    // What the negative leaves behind: the flag, dated to this turn, so
    // the warm-up review can pick the LO next session although it is
    // fresh and at mastery (#112, #167).
    final flaggedAt = DateTime.parse(print['regressedAt'] as String);
    expect(
      DateTime.now().toUtc().difference(flaggedAt),
      lessThan(const Duration(minutes: 1)),
    );
    // "Print" stays done: nothing here re-enrols the student.
    expect(
      harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress'],
      1.0,
    );
    await harness.dispose(tester);

    // ---- The next session: the review the flag asked for ---------------
    // Same student, same data: what the first session left in Cosmos is
    // what the second one boots on.
    final carried = <String, List<Map<String, dynamic>>>{
      for (final container in ['accounts', 'progress', 'lo_beliefs'])
        container: harness.cosmos[container].docs.values.toList(),
    };
    final next = AppHarness(
      llm: ScriptedLlm(reviewScript()),
      extraDocs: carried,
    );
    await openPractice(tester, next, firstExercise: kWarmUpExercise);
    expect(
      pills(tester),
      contains(contains('one review question on Print')),
      reason: 'no pill announced the review on the flagged LO',
    );
    await sendAndWait(tester, next, nextExercise: kExercise);

    final review = turn(next);
    expect(review['isWarmUp'], isTrue);
    expect(review['subgoalId'], 's1');
    expect(review['targetLOIds'], ['lo-print']);
    expect(
      (review['selectionReason'] as Map)['chosenReason'],
      contains('regressed'),
    );
    expect(review.containsKey('reviewFlags'), isFalse);

    // The review is the measurement that counts: a direct probe of
    // `lo-print` at full weight on the decayed (5, 1), clock reset, flag
    // cleared. The LO is back on the ordinary staleness clock.
    final reviewed = storedPrint(next)!;
    expect(reviewed.containsKey('regressedAt'), isFalse);
    final writtenAt = DateTime.parse(reviewed['lastUpdatedAt'] as String);
    expect(
      DateTime.now().toUtc().difference(writtenAt),
      lessThan(const Duration(minutes: 1)),
    );
    final decayed = applyDecay(
      alpha: 5,
      beta: 1,
      lastUpdatedAt: weeksAgo,
      now: writtenAt,
    );
    final onPrint = (review['appliedSignals'] as List).cast<Map>().single;
    expect(onPrint['loId'], 'lo-print');
    expect(onPrint['subgoalId'], 's1');
    // A strong positive at the plan's difficulty: never less than the base
    // weight, and exactly what the doc gained.
    expect(onPrint['alphaDelta'], greaterThanOrEqualTo(2.0));
    expect(
      reviewed['alpha'],
      closeTo(decayed.alpha + (onPrint['alphaDelta'] as num), 1e-9),
    );
    expect(next.llm!.remaining, 0);

    await next.dispose(tester);
  });

  testWidgets('an earlier LO the student was never probed on gets neither '
      'a belief doc nor a flag: nothing to review, nothing in debit', (
    tester,
  ) async {
    final harness = AppHarness(
      llm: ScriptedLlm(script()),
      extraDocs: {
        'progress': [printDone()],
      },
    );
    await answerOnce(tester, harness);

    expect(
      storedPrint(harness),
      isNull,
      reason: 'a belief doc was created for lo-print by a negative alone',
    );
    final t = turn(harness);
    // The grader's signal is on record; the app applied only the target's
    // and flagged nothing.
    expect(
      (t['loSignals'] as List).cast<Map>().map((s) => s['loId']),
      containsAll(['lo-var', 'lo-print']),
    );
    expect((t['appliedSignals'] as List).cast<Map>().single['loId'], 'lo-var');
    expect(t.containsKey('reviewFlags'), isFalse);

    await harness.dispose(tester);
  });
}
