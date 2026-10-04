// End-to-end (#230): the subgoal bar a student watches while practising is
// one segment per LO, and it moves from the first right answer instead of
// sitting on 0 until LOs are mastered.
//
// The teacher saw students get frustrated at the start of a new subgoal:
// the bar stayed on 0 for a long time and then jumped. One right answer on
// hard leaves an LO at μ 0.79, just under the mastery bar (§4.1), and the
// tutor asks every LO once before it asks one twice (§2.1) — so every LO
// sat at 0.79 until the second round, when they fell over one after the
// other. Now each non-optional LO is a segment: empty, half (one right
// answer away) or full (mastered or stuck); a half segment empties only
// after a question on that LO itself that is not right, not on a negative
// from the side. Only the display: the `progress` doc keeps the mastered
// share.
//
// The student here is on hard, on "Print" with two LOs and an optional one
// (already mastered, so no question goes to it). The flow:
//   1. lo-a right               → [half, empty]  (cached share still 0)
//   2. lo-b right, lo-a debited from the side
//                               → [half, half]   (lo-a held)
//   3. lo-a wrong               → [empty, half]
//   4. lo-b right               → [empty, full]  (cached share 0.5)
// checked on the segments in the objective banner, their tooltip, and the
// 2px ambient line at the top of the window.
//
// Real app, real navigation, real practice view, editor, banner and top
// bar, real TutorService → conductor → Cosmos services. Only the model is
// scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/subgoal_segments.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/subgoal_progress_bar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const List<String> _exercises = [
  'print(___)',
  'print("a", ___)',
  'print(___ + "!")',
  'print(1, ___)',
  'print("klaar", ___)',
];

Map<String, String> _signal(String loId, String kind) => {
  'subgoalId': 's1',
  'loId': loId,
  'signal': kind,
  'strength': 'strong',
};

/// The student on `hard`, with a window of ten right answers there — the
/// one wrong answer of this flow demotes nothing (§5.2).
Map<String, dynamic> _hardStudent() {
  final t0 = DateTime.now().toUtc().subtract(const Duration(days: 2));
  return {
    ...accountDoc(studentIdentity),
    'calibration': {
      'difficulty': 'hard',
      'recentAnswers': [
        for (var i = 0; i < 10; i++)
          {
            'quality': 'correct',
            'difficulty': 'hard',
            'at': t0.add(Duration(minutes: i)).toIso8601String(),
          },
      ],
      'recentQuestionTypes': const <String>[],
    },
  };
}

/// The optional LO, mastered a while ago: no question goes to it.
Map<String, dynamic> _optionalMastered() {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return LoBelief(
    subgoalId: 's1',
    loId: 'lo-c',
    alpha: 9,
    beta: 1,
    lastUpdatedAt: at,
    lastPositiveAtCalibratedAt: at,
    firstMasteredAt: at,
  ).toMap(uid: kStudentUid);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Future<void> waitForExercise(WidgetTester tester, int i) => pumpUntil(
    tester,
    () => editorText(tester) == _exercises[i],
    timeout: const Duration(seconds: 30),
    reason: 'exercise ${i + 1} never reached the editor',
  );

  List<LoDisplayState> segments(WidgetTester tester) => [
    for (final s in tester.widgetList<LoSegment>(find.byType(LoSegment)))
      s.state,
  ];

  Future<void> waitForSegments(
    WidgetTester tester,
    List<LoDisplayState> expected,
  ) => pumpUntil(
    tester,
    () => listEquals(segments(tester), expected),
    timeout: const Duration(seconds: 30),
    reason: 'the bar never showed $expected (last: ${segments(tester)})',
  );

  /// The share the 2px line at the top of the window fills.
  double ambientShare(WidgetTester tester) => tester
      .widget<AnimatedFractionallySizedBox>(
        find.descendant(
          of: find.byType(AmbientProgress),
          matching: find.byType(AnimatedFractionallySizedBox),
        ),
      )
      .widthFactor!;

  testWidgets('the subgoal bar is a segment per LO: half after the first '
      'right answer on hard, held against a negative from the side, emptied '
      'by a wrong answer on the LO itself, full when mastered', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Print een zin.', code: _exercises[0]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-a', 'positive')],
      ),
      completeCodeReply(text: 'Print twee waarden.', code: _exercises[1]),
      codeFeedbackReply(
        text: 'Juist, al liep de zin zelf mis.',
        quality: 'correct',
        loSignals: [_signal('lo-b', 'positive'), _signal('lo-a', 'negative')],
      ),
      completeCodeReply(text: 'Nog een zin.', code: _exercises[2]),
      codeFeedbackReply(
        text: 'Niet juist: er komt geen tekst op het scherm.',
        quality: 'wrong',
        loSignals: [_signal('lo-a', 'negative')],
      ),
      completeCodeReply(text: 'Weer twee waarden.', code: _exercises[3]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-b', 'positive')],
      ),
      completeCodeReply(text: 'Nog eens een zin.', code: _exercises[4]),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'accounts': [_hardStudent()],
        // "Print" without its lesson, so the leerpad opens the editor.
        'goals': [
          goalDoc(
            id: 's1',
            title: 'Print',
            parentId: 'r1',
            order: 1000,
            objectives: [
              objective('lo-a', 'Print a sentence'),
              objective('lo-b', 'Print several values at once'),
              {...objective('lo-c', 'Choose the separator'), 'optional': true},
            ],
          ),
        ],
        'lo_beliefs': [_optionalMastered()],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    const empty = LoDisplayState.empty;
    const half = LoDisplayState.half;
    const full = LoDisplayState.full;

    // Two segments — the optional LO has none — both empty.
    await waitForExercise(tester, 0);
    await waitForSegments(tester, [empty, empty]);
    expect(
      find.byTooltip('0 parts mastered, 0 almost, 2 still to do'),
      findsOneWidget,
    );

    double cachedShare() =>
        (harness.cosmos['progress'].docs['${kStudentUid}_s1']!['progress']
                as num)
            .toDouble();

    // 1. The first right answer on hard: μ 0.79, not mastered — and the
    //    bar moves anyway. The cached share does not.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 1);
    await waitForSegments(tester, [half, empty]);
    expect(
      find.byTooltip('0 parts mastered, 1 almost, 1 still to do'),
      findsOneWidget,
    );
    expect(cachedShare(), 0.0);
    expect(ambientShare(tester), closeTo(0.25, 1e-9));

    // 2. A right answer on lo-b, with a negative on lo-a from the side:
    //    lo-a is out of reach of one answer now, but its segment holds.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 2);
    await waitForSegments(tester, [half, half]);
    expect(
      find.byTooltip('0 parts mastered, 2 almost, 0 still to do'),
      findsOneWidget,
    );
    expect(cachedShare(), 0.0);
    expect(ambientShare(tester), closeTo(0.5, 1e-9));

    // 3. A wrong answer on lo-a itself empties it.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 3);
    await waitForSegments(tester, [empty, half]);

    // 4. lo-b right again: mastered, full.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 4);
    await waitForSegments(tester, [empty, full]);
    expect(
      find.byTooltip('1 part mastered, 0 almost, 1 still to do'),
      findsOneWidget,
    );
    expect(cachedShare(), 0.5);
    expect(ambientShare(tester), closeTo(0.5, 1e-9));

    // The bar sits in the objective banner, above the editor.
    expect(
      tester.getRect(find.byType(SubgoalProgressBar)).bottom,
      lessThan(tester.getRect(find.byType(CodeField)).top),
    );

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
