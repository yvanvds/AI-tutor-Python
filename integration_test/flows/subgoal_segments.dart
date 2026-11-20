// End-to-end (#230, #325): the subgoal bar a student watches while
// practising is one segment per LO, and it shows the real state of each.
//
// #230 made the bar a segment per LO, empty, half or full, so it moved from
// the first right answer. In the lesson of 2026-11-20 a student answered
// right and the bar did not move: one LO was stuck and so already full
// ("stuck looks full"), the app kept asking it, and a full segment stayed
// full. Now each segment counts down the right answers its LO still needs,
// at the level the app asks it, and fills along with that number — a new
// LO empty, a mastered one full. A stuck LO shows its real count, a
// segment goes down after a wrong answer or a negative from the side, and
// says why in its popup; the mastery stamp gets a tick of its own that
// stays when the fill drops. The segment of the exercise on screen is
// framed. Only the display: the `progress` doc keeps the mastered share.
//
// The student is on hard, on "Print" with two LOs and an optional one
// (already mastered, so no question goes to it). lo-b is stuck: six own
// questions, μ 0.27. A new LO on hard needs two right answers.
//   0. start                     → lo-a 2, lo-b 4 (stuck, not full); the
//                                  first question is on lo-b, framed
//   1. lo-b right                → lo-b 3
//   2. lo-a right                → lo-a 1, half filled; framed
//   3. lo-b right                → lo-b 2
//   4. lo-a right                → lo-a 0, full, ticked (cached share 0.5)
//   5. lo-b wrong, and a mistake on lo-a from the side
//                                → lo-b 3 "after an answer that was not
//                                  right"; lo-a 2 "after a mistake on this in
//                                  a question about something else", its
//                                  tick still there (cached share 0)
// checked on the segments in the objective banner, their popups (hover
// and tap), the bar's tooltip, the 2px ambient line at the top of the
// window — and at a narrow window.
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
import 'package:flutter/gestures.dart';
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
  'print("nog", ___)',
];

const _sentence = 'Print a sentence';
const _values = 'Print several values at once';

/// A window narrower than the harness's 1280 px, as on a small laptop with
/// the chat open.
const double _narrow = 700;

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

/// lo-b, stuck: six own questions, none right, μ 0.27 (§4.4).
Map<String, dynamic> _stuck() {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return LoBelief(
    subgoalId: 's1',
    loId: 'lo-b',
    alpha: 1.5,
    beta: 4,
    lastUpdatedAt: at,
    lastProbedAt: at,
    ownQuestions: 6,
    ownQuestionsRight: 0,
    ownQuestionsRightNonMcq: 0,
  ).toMap(uid: kStudentUid);
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

  List<LoSegment> segmentWidgets(WidgetTester tester) =>
      tester.widgetList<LoSegment>(find.byType(LoSegment)).toList();

  /// The right answers to go in each segment.
  List<int> counts(WidgetTester tester) => [
    for (final s in segmentWidgets(tester)) s.entry.toGo,
  ];

  /// The LO of the framed segment, if any.
  String? framed(WidgetTester tester) =>
      segmentWidgets(tester)
          .where((s) => s.current)
          .map((s) => s.entry.loId)
          .singleOrNull;

  Future<void> waitForCounts(WidgetTester tester, List<int> expected) =>
      pumpUntil(
        tester,
        () => listEquals(counts(tester), expected),
        timeout: const Duration(seconds: 30),
        reason: 'the bar never showed $expected (last: ${counts(tester)})',
      );

  Finder segment(String loId) => find.byKey(ValueKey('lo-segment-$loId'));

  /// The number drawn in [loId]'s segment, or `null` when it shows none.
  /// Its open popup is in the segment's subtree too (an overlay portal),
  /// as rich text: only plain texts are the number.
  String? numberIn(WidgetTester tester, String loId) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: segment(loId), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .nonNulls
        .toSet();
    return texts.isEmpty ? null : texts.single;
  }

  bool tickIn(String loId) => find
      .descendant(of: segment(loId), matching: find.byIcon(Icons.check_rounded))
      .evaluate()
      .isNotEmpty;

  /// The share the 2px line at the top of the window fills.
  double ambientShare(WidgetTester tester) => tester
      .widget<AnimatedFractionallySizedBox>(
        find.descendant(
          of: find.byType(AmbientProgress),
          matching: find.byType(AnimatedFractionallySizedBox),
        ),
      )
      .widthFactor!;

  testWidgets('each segment counts down the right answers its LO still '
      'needs: a stuck LO is not full, a wrong answer or a mistake from the '
      'side takes a segment down and its popup says why, the tick of a '
      'demonstrated LO stays, and the LO of the exercise is framed', (
    tester,
  ) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Print twee waarden.', code: _exercises[0]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-b', 'positive')],
      ),
      completeCodeReply(text: 'Print een zin.', code: _exercises[1]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-a', 'positive')],
      ),
      completeCodeReply(text: 'Weer twee waarden.', code: _exercises[2]),
      codeFeedbackReply(
        text: 'Juist.',
        quality: 'correct',
        loSignals: [_signal('lo-b', 'positive')],
      ),
      completeCodeReply(text: 'Nog een zin.', code: _exercises[3]),
      codeFeedbackReply(
        text: 'Helemaal juist.',
        quality: 'correct',
        loSignals: [_signal('lo-a', 'positive')],
      ),
      completeCodeReply(text: 'Nog eens twee waarden.', code: _exercises[4]),
      codeFeedbackReply(
        text: 'Niet juist: er komt geen tekst op het scherm.',
        quality: 'wrong',
        loSignals: [_signal('lo-b', 'negative'), _signal('lo-a', 'negative')],
      ),
      completeCodeReply(text: 'Weer een zin.', code: _exercises[5]),
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
              objective('lo-a', _sentence),
              objective('lo-b', _values),
              {...objective('lo-c', 'Choose the separator'), 'optional': true},
            ],
          ),
        ],
        'lo_beliefs': [_stuck(), _optionalMastered()],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    double cachedShare() =>
        ((harness.cosmos['progress'].docs['${kStudentUid}_s1']?['progress']
                    as num?) ??
                0)
            .toDouble();

    // 0. Two segments — the optional LO has none. lo-a new: two right
    //    answers on hard. lo-b stuck: its real count, not full. The app
    //    asks the stuck LO first, and its segment is framed.
    await waitForExercise(tester, 0);
    await waitForCounts(tester, [2, 4]);
    expect(numberIn(tester, 'lo-a'), '2');
    expect(numberIn(tester, 'lo-b'), '4');
    expect(segmentWidgets(tester).map((s) => s.entry.fill).toList(), [
      0.0,
      0.0,
    ]);
    expect(framed(tester), 'lo-b');
    expect(
      find.byTooltip('0 of 2 parts mastered, 6 more right answers to go'),
      findsOneWidget,
    );
    expect(ambientShare(tester), 0.0);

    // 1. lo-b right: one fewer.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 1);
    await waitForCounts(tester, [2, 3]);
    expect(framed(tester), 'lo-a');

    // 2. lo-a right: one right answer away, half filled. The cached share
    //    does not move.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 2);
    await waitForCounts(tester, [1, 3]);
    expect(segmentWidgets(tester).first.entry.fill, 0.5);
    expect(cachedShare(), 0.0);
    expect(ambientShare(tester), closeTo(0.25, 1e-9));

    // 3. lo-b right again.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 3);
    await waitForCounts(tester, [1, 2]);

    // 4. lo-a right: mastered — full, no number, the tick of its stamp.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 4);
    await waitForCounts(tester, [0, 2]);
    expect(numberIn(tester, 'lo-a'), isNull);
    expect(tickIn('lo-a'), isTrue);
    expect(tickIn('lo-b'), isFalse);
    expect(cachedShare(), 0.5);
    expect(ambientShare(tester), closeTo(0.5, 1e-9));
    expect(
      find.byTooltip('1 of 2 parts mastered, 2 more right answers to go'),
      findsOneWidget,
    );

    // 5. lo-b wrong, with a mistake on lo-a from the side: both go up, and
    //    lo-a keeps its tick. The next question is on lo-a, framed.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, 5);
    await waitForCounts(tester, [2, 3]);
    expect(tickIn('lo-a'), isTrue);
    expect(numberIn(tester, 'lo-a'), '2');
    expect(framed(tester), 'lo-a');
    expect(
      segmentWidgets(tester).first.entry.rose,
      LoDisplayRise.otherQuestion,
    );
    expect(segmentWidgets(tester).last.entry.rose, LoDisplayRise.notRight);
    await pumpUntil(
      tester,
      () => cachedShare() == 0.0,
      reason: 'the cached share never followed lo-a back under the bar',
    );
    expect(ambientShare(tester), 0.0);

    // The popups, by hover: the sentence, the state, why it went up, and
    // the exercise on screen.
    const lowerPopup =
        '$_values\n3 more right answers\n'
        'Went up after an answer that was not right.';
    const framedPopup =
        '$_sentence\n2 more right answers · demonstrated\n'
        'Went up after a mistake on this in a question about something '
        'else.\nYour current exercise is about this.';
    expect(find.byTooltip(lowerPopup), findsOneWidget);
    expect(find.byTooltip(framedPopup), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(segment('lo-b')));
    await pumpUntilFound(tester, find.text(lowerPopup));

    // ... and by tap.
    await mouse.moveTo(Offset.zero);
    await pumpUntil(
      tester,
      () => find.text(lowerPopup).evaluate().isEmpty,
      reason: 'the popup never closed',
    );
    await tester.tap(segment('lo-a'));
    await pumpUntilFound(tester, find.text(framedPopup));

    // The bar sits in the objective banner, above the editor.
    expect(
      tester.getRect(find.byType(SubgoalProgressBar)).bottom,
      lessThan(tester.getRect(find.byType(CodeField)).top),
    );

    // A narrow window: both segments keep their number and tick, side by
    // side inside the banner, without overflow.
    // (No pumpAndSettle: the practice view never settles — the editor's
    // cursor blinks.)
    tester.view.physicalSize =
        Size(_narrow, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
    await pumpUntil(
      tester,
      () => tester.getRect(find.byType(SubgoalProgressBar)).right <= _narrow,
      reason: 'the bar never fit the narrow window',
    );
    // Whatever slides on a resize (the chat panel) comes to rest.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(SubgoalProgressBar));
    expect(bar.right, lessThanOrEqualTo(_narrow));
    for (final lo in ['lo-a', 'lo-b']) {
      final rect = tester.getRect(segment(lo));
      expect(rect.width, greaterThan(40), reason: lo);
      expect(rect.left, greaterThanOrEqualTo(bar.left - 0.01), reason: lo);
      expect(rect.right, lessThanOrEqualTo(bar.right + 0.01), reason: lo);
    }
    expect(numberIn(tester, 'lo-a'), '2');
    expect(numberIn(tester, 'lo-b'), '3');
    expect(tickIn('lo-a'), isTrue);

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
