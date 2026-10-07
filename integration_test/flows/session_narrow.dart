// End-to-end (#259): in a 700 px window the session keeps the lesson and the
// exercise inside it.
//
// Next to the 72 px sidebar a 700 px window leaves the session 628 px, and
// the chat panel took 460 of them: the row above the editor in Practice
// (RunControls) ran up to 48 px past the 168 px that were left, and in the
// theory view the footer ("Previous / Try it yourself") ran 243 px past it
// while the chat folded after the window was made narrow. Now the full chat
// takes at most half the session, also mid-slide, and the footer shows the
// richest form of itself that fits — first the XP caption goes, then the
// words on the buttons, each kept in a tooltip — so a student who chose to
// keep the chat open on a small screen still has a whole footer. A long goal
// title in the header ends in an ellipsis instead of running past the
// counter: the root goal here has the length of a real one.
//
// What only a full-app run pins: the real font, the real sidebar next to the
// session, the real lesson WebView and editor in the column that is left,
// and the real window made narrow under a running app. Any overflow on the
// way fails the flow.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/session_narrow.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// The narrow window of #258 and #259.
const double _narrow = 700;

/// A root goal as long as the longest in the real curriculum.
const String _longTitle =
    'Be able to write and understand very basic Python scripts';

Finder _panel() => find.byKey(const Key('chat-panel'));
Finder _footer() => find.byKey(const Key('explain-footer'));
Finder _surface() => find.descendant(
  of: find.byType(LessonHtmlView),
  matching: find.byType(Texture),
);

double _panelWidth(WidgetTester tester) => tester.getSize(_panel()).width;
double _sessionWidth(WidgetTester tester) =>
    tester.getSize(find.byType(SessionView)).width;

void _resize(WidgetTester tester, double width) {
  tester.view.physicalSize =
      Size(width, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
}

Rect _window(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

/// Every word and icon of [of] on screen, whole, inside [outer].
void _partsInside(WidgetTester tester, Finder of, Rect outer, String where) {
  final parts = find.descendant(
    of: of,
    matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
  );
  expect(parts, findsWidgets, reason: where);
  for (final part in parts.evaluate()) {
    final box = part.renderObject! as RenderBox;
    final r = box.localToGlobal(Offset.zero) & box.size;
    expect(_inside(outer, r), isTrue, reason: '$where: ${part.widget} at $r');
  }
}

/// The theory view's header and footer inside the lesson column, and the
/// column inside the window.
void _lessonLaidOut(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: where);
  final lesson = tester.getRect(find.byType(ExplainView));
  expect(_inside(_window(tester), lesson), isTrue, reason: '$where: $lesson');
  _partsInside(tester, _footer(), lesson, '$where, footer');
  final counter = tester.getRect(find.text('1 / 2'));
  expect(_inside(lesson, counter), isTrue, reason: '$where: counter $counter');
  final pill = tester.getRect(find.text(_longTitle.toUpperCase()));
  expect(pill.left, greaterThanOrEqualTo(lesson.left), reason: where);
  expect(pill.right, lessThan(counter.left), reason: '$where: pill $pill');
}

/// "Try it yourself", spelled out or, in the narrowest footer, its arrow.
Finder _tryIt() {
  final word = find.text('Try it yourself');
  return word.evaluate().isNotEmpty ? word : find.byTooltip('Try it yourself');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('at 700 px the lesson and the exercise stay inside the window: '
      'the chat takes half the session, also while it folds after a resize, '
      'and the footer and the row above the editor make do', (tester) async {
    final harness = AppHarness(
      extraDocs: {
        'goals': [goalDoc(id: 'r1', title: _longTitle)],
      },
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);

    // The lesson, in the window the runner creates: the 460 px chat beside
    // it, and the whole footer.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntil(
      tester,
      () => harness.lessonRunner.ran.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page never loaded',
    );
    await pumpUntilFound(tester, _surface());
    await pumpUntilFound(tester, find.text('1 / 2'));
    expect(_panelWidth(tester), chatPanelWidth);
    expect(find.text('+100 XP on completion'), findsOneWidget);
    _lessonLaidOut(tester, 'lesson at 1280 px');

    // Made narrow: with no choice stored the chat folds (#138). Every frame
    // of the slide leaves the lesson at least half the session, and the
    // lesson's header and footer inside it.
    _resize(tester, _narrow);
    await tester.pump();
    var frames = 0;
    while (_panelWidth(tester) != chatCollapsedWidth) {
      expect(frames++, lessThan(200), reason: 'the chat never folded');
      final half = _sessionWidth(tester) / 2;
      expect(_panelWidth(tester), lessThanOrEqualTo(half + 0.01));
      _lessonLaidOut(tester, 'frame $frames of the fold at $_narrow px');
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames, greaterThan(1), reason: 'the fold was not a slide');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('+100 XP on completion'), findsOneWidget);
    _lessonLaidOut(tester, 'folded at $_narrow px');

    // Open on a small screen, by choice: half the session each, and the
    // footer makes do with less. Its buttons still work.
    await tester.tap(find.byTooltip('Show chat'));
    final half = _sessionWidth(tester) / 2;
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == half,
      reason: 'the chat never opened to half the session',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.container.read(chatCollapsedProvider), isFalse);
    expect(tester.getSize(find.byType(ExplainView)).width, half);
    expect(find.textContaining('XP on completion'), findsNothing);
    _lessonLaidOut(tester, 'chat open at $_narrow px');

    await tester.tap(_tryIt());
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilGone(tester, find.byType(ExplainView));
    expect(harness.container.read(modeProvider), SessionMode.practice);

    // Practice: the same half, and the row above the editor whole inside
    // the exercise — Run and Reset on the left, hint and send on the right.
    await pumpUntilFound(tester, find.byType(RunControls));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'practice at $_narrow px');
    expect(_panelWidth(tester), half);
    final exercise = tester.getRect(find.byType(PracticeView));
    expect(exercise.width, half);
    final controls = tester.getRect(find.byType(RunControls));
    expect(_inside(exercise, controls), isTrue, reason: 'controls $controls');
    _partsInside(tester, find.byType(RunControls), controls, 'run controls');
    for (final tip in ['Reset output', 'Ask for a hint', 'Send to tutor']) {
      final button = find.descendant(
        of: find.byType(RunControls),
        matching: find.byTooltip(tip),
      );
      expect(button, findsOneWidget, reason: tip);
      expect(
        _inside(controls, tester.getRect(button)),
        isTrue,
        reason: '$tip at ${tester.getRect(button)}',
      );
    }
    expect(
      find.descendant(of: find.byType(RunControls), matching: find.text('Run')),
      findsOneWidget,
    );

    // Wide again: the chat is its own 460 px.
    _resize(tester, kRunnerWindowSize.width);
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatPanelWidth,
      reason: 'the chat never grew back to $chatPanelWidth px',
    );
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
