// End-to-end (#221): the class podium. Gold, silver and bronze for the first
// three students of a class to finish a subgoal — and only the winner ever
// sees a medal.
//
// What only the running app can show:
//
//   - the graded answer that moves the student past a subgoal for the first
//     time claims the first free place on their class's podium: with gold
//     already someone else's, `create` on place 1 is refused (409) and place 2
//     is the student's — a doc in the `podium` partition of `config` with the
//     student's uid and nothing else about them;
//   - the medal lands on the account doc with the other badges and is
//     announced like them, but only once the goal-reached celebration is
//     gone — the notice never lands on top of it;
//   - the trophy case shows the student's own medal under "Class podium",
//     with no ranking and nobody else's place or name anywhere.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader payload → conductor → mastery → advance → badge
// service → podium docs → account doc → notice → trophy case. Only the model
// is scripted (`ScriptedLlm`, raw assistant text through the production
// parser); Cosmos is the in-memory fake.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/class_podium.dart -d windows

import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _class = '6TEST';
const String _rival = 'it-rival-student';
const String _exercise = 'stad = ___\nprint("Welkom in " + stad)';
const String _nextExercise = 'for i in range(___):\n    print(i)';

/// The exercise on "Variables", the grade that masters `lo-var` and so
/// finishes the subgoal, the status report the app asks for on a finished
/// subgoal, and the first exercise of "Loops".
List<String> _script() => [
  completeCodeReply(text: 'Vul de stad in.', code: _exercise),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's2',
        'loId': 'lo-var',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  ),
  llmEnvelope(
    text: 'Sam kent variabelen.',
    meta:
        '{"type":"status_summary","stats":{"hints_used":0,'
        '"common_issues":[],"last_exercise_type":"complete_code"}}',
  ),
  completeCodeReply(text: 'Nu een lus.', code: _nextExercise),
];

/// "Variables" with one LO, and "Loops" for the walk to go on to.
List<Map<String, dynamic>> _curriculum() => [
  goalDoc(
    id: 's2',
    title: 'Variables',
    parentId: 'r1',
    order: 2000,
    objectives: [objective('lo-var', 'Assign a value to a name')],
  ),
  goalDoc(
    id: 's3',
    title: 'Loops',
    parentId: 'r1',
    order: 3000,
    objectives: [objective('lo-loop', 'Repeat with a for loop')],
  ),
];

/// "Print" is done, so the walk lands on "Variables".
Map<String, dynamic> _printDone() => {
  'id': '${kStudentUid}_s1',
  'uid': kStudentUid,
  'goalId': 's1',
  'progress': 1.0,
  'advancedAt': '2026-09-01T10:00:00Z',
  'updatedAt': '2026-09-01T10:00:00Z',
  'lastSessionAt': '2026-09-01T10:00:00Z',
};

/// One strong positive short of mastery, calibrated positive on record:
/// (3, 1) reads 0.75; the grade makes it (5, 1), 0.83 — mastered, and with
/// it the subgoal.
Map<String, dynamic> _almostMastered(DateTime at) => {
  'id': '${kStudentUid}_s2_lo-var',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's2',
  'loId': 'lo-var',
  'alpha': 3,
  'beta': 1,
  'lastUpdatedAt': at.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': at.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Finder toast() => find.byKey(const ValueKey('badge-toast'));

  Finder inToast(Finder what) => find.descendant(of: toast(), matching: what);

  testWidgets('finishing a subgoal second in the class: silver, announced '
      'after the celebration, and only the student\'s own medal in the '
      'trophy case', (tester) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      // A school morning (#235): on a weekend night the answer earns "Night
      // owl" and "Weekend warrior" too, and from three badges at once the
      // notice is one summary, not the "Silver" one this flow looks for.
      turnClockStart: kWeekdayMorning,
      llm: ScriptedLlm(_script()),
      extraDocs: {
        'accounts': [
          {
            ...accountDoc(studentIdentity),
            'className': _class,
            'oefeningCount': 1,
            // Looked at before: only what this answer earns is announced.
            'badges': {
              'helloWorld': {'tier': 1, 'earnedAt': '2026-09-01T10:00:00.000Z'},
            },
          },
        ],
        'goals': _curriculum(),
        'progress': [_printDone()],
        'lo_beliefs': [_almostMastered(now)],
        // Someone else in the class finished "Variables" first.
        'config': [
          {
            'id': 'podium_${_class}_s2_1',
            'type': 'podium',
            'className': _class,
            'subgoalId': 's2',
            'place': 1,
            'uid': _rival,
            'awardedAt': '2026-09-20T10:00:00.000Z',
          },
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == _exercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    expect(toast(), findsNothing);

    await tester.tap(find.byTooltip('Send to tutor'));

    // The grade finishes "Variables" and the app celebrates; the medal's
    // notice waits for it.
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    // The place is claimed by now, or soon: the notice still waits.
    await pumpUntil(
      tester,
      () => harness.cosmos['config'].docs['podium_${_class}_s2_2'] != null,
      timeout: const Duration(seconds: 30),
      reason: 'no podium place was claimed',
    );
    expect(toast(), findsNothing, reason: 'not on top of the celebration');
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);

    await pumpUntilFound(
      tester,
      inToast(find.text('Silver: Variables')),
      timeout: const Duration(seconds: 30),
    );
    expect(
      inToast(
        find.text('You were the second in your class to finish this topic.'),
      ),
      findsOneWidget,
    );

    // Silver: gold was someone else's, and stays theirs.
    final silver = harness.cosmos['config'].docs['podium_${_class}_s2_2']!;
    expect(silver['type'], 'podium');
    expect(silver['uid'], kStudentUid);
    expect(silver['className'], _class);
    expect(silver['subgoalId'], 's2');
    expect(silver['place'], 2);
    expect(silver.keys, isNot(contains('firstName')));
    expect(
      harness.cosmos['config'].docs['podium_${_class}_s2_1']!['uid'],
      _rival,
    );
    expect(harness.cosmos['config'].docs['podium_${_class}_s2_3'], isNull);
    // The settings next to it are untouched.
    expect(harness.cosmos['config'].docs['global'], isNotNull);

    // The medal sits with the other badges on the account doc.
    final badges =
        harness.cosmos['accounts'].docs[kStudentUid]!['badges'] as Map;
    final medal = badges['podium:s2'] as Map;
    expect(medal['tier'], 2);
    expect(medal['place'], 2);
    expect(medal['awardedBy'], 'podium');
    expect(medal['earnedAt'], silver['awardedAt']);
    expect(badges['helloWorld'], {
      'tier': 1,
      'earnedAt': '2026-09-01T10:00:00.000Z',
    });

    // The trophy case: the student's own medal, nobody else's. Opened from
    // the notice, before it times out.
    await tester.tap(inToast(find.text('See your trophy case')));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    await pumpUntilGone(tester, toast());
    final section = find.byKey(const ValueKey('badges-section-podium'));
    final scrollable = find
        .descendant(
          of: find.byType(PrijzenkastPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(section, 200, scrollable: scrollable);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(of: section, matching: find.text('Class podium')),
      findsOneWidget,
    );
    final tile = find.byKey(const ValueKey('badge-tile-podium:s2'));
    // The case shows the medal once the next poll of the account doc (5 s)
    // brings it (#236). Until #235 this passed only with a second notice —
    // "Weekend warrior" or "Night owl" — keeping the toast up that long; on
    // a weekday morning the toast is gone well before the poll.
    await pumpUntilFound(
      tester,
      find.descendant(of: tile, matching: find.text('Silver: Variables')),
    );
    expect(
      find.descendant(of: section, matching: find.byType(BadgeTileCard)),
      findsOneWidget,
      reason: 'only the student\'s own medal',
    );
    expect(find.textContaining(_rival), findsNothing);
    expect(find.textContaining('Gold'), findsNothing);
    final board = harness.container.read(badgeBoardProvider)!;
    expect(board.podium.map((t) => t.badge.id), ['podium:s2']);

    // The walk went on to "Loops" meanwhile; let the tutor settle first.
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
    );
    await harness.dispose(tester);
  });

  testWidgets('a student without a class does not take part: no place '
      'claimed, and the trophy case says why', (tester) async {
    final now = DateTime.now().toUtc();
    final harness = AppHarness(
      // Same school morning as above (#235): no time-bound badge's notice.
      turnClockStart: kWeekdayMorning,
      llm: ScriptedLlm(_script()),
      extraDocs: {
        'accounts': [
          {
            ...accountDoc(studentIdentity),
            'oefeningCount': 1,
            'badges': {
              'helloWorld': {'tier': 1, 'earnedAt': '2026-09-01T10:00:00.000Z'},
            },
          },
        ],
        'goals': _curriculum(),
        'progress': [_printDone()],
        'lo_beliefs': [_almostMastered(now)],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == _exercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    await tester.tap(find.byTooltip('Send to tutor'));
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);
    await pumpUntil(
      tester,
      () => editorText(tester) == _nextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next subgoal\'s exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
    );
    // The advance is on the record, and still: no podium.
    final turn = harness.cosmos['turn_history'].docs.values.single;
    expect(turn['subgoalAdvanced'], isTrue);
    final settle = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(settle)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      harness.cosmos['config'].docs.keys.where((k) => k.startsWith('podium_')),
      isEmpty,
    );
    final badges =
        harness.cosmos['accounts'].docs[kStudentUid]!['badges'] as Map;
    expect(badges.containsKey('podium:s2'), isFalse);

    await tester.tap(find.byTooltip('Trophy case'));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    final board = harness.container.read(badgeBoardProvider)!;
    expect(board.inClass, isFalse);
    expect(board.podium, isEmpty);
    final section = find.byKey(const ValueKey('badges-section-podium'));
    await tester.scrollUntilVisible(
      section,
      200,
      scrollable: find
          .descendant(
            of: find.byType(PrijzenkastPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: section,
        matching: find.text(
          "You're not in a class yet, so you don't take part yet.",
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: section, matching: find.byType(BadgeTileCard)),
      findsNothing,
    );

    await harness.dispose(tester);
  });
}
