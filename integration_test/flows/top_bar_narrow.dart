// End-to-end (#258): the top bar keeps its parts inside a narrow window.
//
// Under ~820 px the stat strip at the top right (the streak chip and the
// level pill) ran 59 px past its place at 700 px, on every page: the bar
// split its width in two halves around the mode switcher, the switcher kept
// its ~220 px even where it was invisible (outside Session), and the strip
// did not shrink. Now the switcher gives its place back outside Session,
// and the strip drops the word "days" first and then the XP count — both
// still in a tooltip — when it has less room.
//
// What only a full-app run pins: the real font (the test font makes every
// part wider, see test/features/shell/top_bar_test.dart), the real sidebar
// next to the bar, the real pages under it, and the real window resized
// under a running app.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/top_bar_narrow.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// The narrow window of #258.
const double _narrow = 700;

/// The bar's horizontal padding (`AppSpacing.xxl`).
const double _padding = 28;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final bar = find.byType(TopBar);
  final modes = find.byType(ModeSwitcher);
  final stats = find.byType(StatStrip);
  final greeting = find.text('Hi Sam,');

  /// What is on screen in the strip: the form that fits, and nothing else.
  Finder inStrip(String text) =>
      find.descendant(of: stats, matching: find.text(text));

  Rect window(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  bool inside(Rect outer, Rect inner) =>
      inner.left >= outer.left - 0.01 &&
      inner.top >= outer.top - 0.01 &&
      inner.right <= outer.right + 0.01 &&
      inner.bottom <= outer.bottom + 0.01;

  /// The greeting, the switcher (when there is one) and the strip inside the
  /// bar's padding, in that order and apart; every word in the strip whole,
  /// inside the strip and inside the window.
  void expectLaidOut(WidgetTester tester, String where) {
    final b = tester.getRect(bar);
    expect(inside(window(tester), b), isTrue, reason: '$where: bar $b');
    final g = tester.getRect(greeting);
    final s = tester.getRect(stats);
    expect(g.left, greaterThanOrEqualTo(b.left + _padding - 0.01));
    expect(s.right, lessThanOrEqualTo(b.right - _padding + 0.01));
    if (modes.evaluate().isEmpty) {
      expect(g.right, lessThan(s.left), reason: '$where: greeting $g');
    } else {
      final m = tester.getRect(modes);
      expect(g.right, lessThan(m.left), reason: '$where: greeting $g');
      expect(m.right, lessThan(s.left), reason: '$where: switcher $m');
    }
    final words = find.descendant(of: stats, matching: find.byType(Text));
    expect(words, findsWidgets, reason: where);
    for (final word in words.evaluate()) {
      final box = word.renderObject! as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      final text = (word.widget as Text).data;
      expect(inside(s, r), isTrue, reason: '$where: "$text" at $r');
      expect(inside(window(tester), r), isTrue, reason: '$where: "$text"');
    }
  }

  testWidgets('at 700 px the top bar stays inside the window on Session and '
      'on the learning path', (tester) async {
    // Started at 700 px rather than resized down to it: a wide window folds
    // its chat on the way down, and the theory view under the bar overflows
    // during that slide (#259) — not this flow's subject.
    final harness = AppHarness(
      windowSize: Size(_narrow, kRunnerWindowSize.height),
    );
    await harness.boot(tester);
    final streak = harness.container.read(profileProvider).streak;

    // Session: the strip makes do with less, and loses nothing for good.
    await pumpUntilFound(tester, inStrip('Level 1'));
    await tester.pump(const Duration(milliseconds: 300));
    expectLaidOut(tester, 'Session at $_narrow px');
    expect(modes, findsOneWidget);
    expect(inStrip('days'), findsNothing);
    expect(inStrip('$streak'), findsOneWidget);
    expect(find.byTooltip('$streak days'), findsOneWidget);
    if (inStrip('0 / 500').evaluate().isEmpty) {
      expect(find.byTooltip('0 / 500'), findsOneWidget);
    }

    // The switcher still works in its narrower bar. Playground, not
    // Practice: next to Practice's 460 px chat the editor's own toolbar
    // does not fit 700 px yet (#259).
    await tester.tap(
      find.descendant(of: modes, matching: find.text('Playground')),
    );
    await pumpUntil(
      tester,
      () => harness.container.read(modeProvider) == SessionMode.playground,
      reason: 'a tap on Playground in the $_narrow px bar did nothing',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expectLaidOut(tester, 'Playground at $_narrow px');

    // The learning path: no switcher, and its place goes to the strip.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilGone(tester, modes);
    expect(find.text('Explain'), findsNothing);
    await pumpUntilFound(tester, inStrip('days'));
    expectLaidOut(tester, 'Learning path at $_narrow px');
    expect(inStrip('0 / 500'), findsOneWidget);
    expect(inStrip('Level 1'), findsOneWidget);

    // Back on Session the switcher comes back, between the two.
    await tester.tap(find.byTooltip('Session'));
    await pumpUntilFound(tester, modes);
    await tester.pump(const Duration(milliseconds: 300));
    expectLaidOut(tester, 'Session again at $_narrow px');

    // And in the runner window everything is spelled out, the switcher
    // centred.
    tester.view.physicalSize = kRunnerWindowSize * tester.view.devicePixelRatio;
    await pumpUntilFound(tester, inStrip('days'));
    await tester.pump(const Duration(milliseconds: 300));
    expectLaidOut(tester, 'Session at 1280 px');
    expect(inStrip('0 / 500'), findsOneWidget);
    expect(
      tester.getRect(modes).center.dx,
      moreOrLessEquals(tester.getRect(bar).center.dx, epsilon: 0.5),
    );

    await harness.dispose(tester);
  });
}
