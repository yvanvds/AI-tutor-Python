// End-to-end (#156): the navigation rail has to fit the window it is given.
//
// The rail grew a section per feature — #25 (Options), #26 (Instructions),
// #99 (Milestones), #129 (Grade formula), #148 (Reports) — inside a plain
// `Column` under a `Spacer()`, which has no room to give. By #148 a
// teacher's rail came to 25 px short of the 720 px window the Windows runner
// creates, and #151's tenth entry overflowed it by 21 px: the sign-out
// clipped off the bottom, and a hard test failure. The workaround was to
// make that entry student-only; this is the rail actually being fixed.
//
// What only a full-app run can pin — and what a widget test structurally
// cannot:
//   - the *real* height budget. `test/features/shell/sidebar_test.dart`
//     mounts the rail alone in the test font, where the same "TEACHER"
//     header measures differently; here the rail sits in the real shell, in
//     the real font, in the window the runner really creates;
//   - that the whole rail is reachable *without* scrolling at 720 px, which
//     is what every other flow relies on when it taps
//     `find.byTooltip('Reports')` with no `ensureVisible`;
//   - the 1366x768 laptop a teacher actually teaches from: minus the
//     taskbar and the title bar the app gets about 688 px, which the rail
//     before this fix already overflowed — nobody had looked;
//   - that on a genuinely short window the destinations scroll instead of
//     clipping, while Options and sign-out stay pinned and tappable, with
//     real pages rendering next to the rail the whole time.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/sidebar_rail.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/reports/reports_page.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// A 1366x768 laptop with the Windows taskbar and the app's title bar taken
/// off — the smallest window a teacher meets without doing anything unusual.
const double _laptopHeight = 688;

/// The same window dragged down to half a screen: shorter than the rail's
/// own content, so the safety net has to carry it.
const double _shortHeight = 600;

/// Every entry a teacher's rail carries at its tallest — an
/// integration-test binary is a debug build, so the developer-gated
/// instructions editor is there too.
const List<String> _entries = [
  'Session',
  'Learning path',
  'Grade formula',
  'Goals',
  'Lesson content',
  'Instructions',
  'Students',
  'Milestones',
  'Reports',
];

/// The scrolling half of the rail: the destinations, without the pinned
/// Options + sign-out strip under it.
Finder _destinations() => find.byKey(const Key('sidebar-destinations'));

ScrollPosition _railScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _destinations(), matching: find.byType(Scrollable)),
    )
    .position;

/// The room left under the last destination before the pinned strip — how
/// many more entries the rail could take at this window height.
double _slackUnderLast(WidgetTester tester) =>
    tester.getRect(_destinations()).bottom -
    tester.getRect(find.byTooltip(_entries.last)).bottom;

/// Drags the window's bottom edge to [height], keeping the runner's width.
void _resize(WidgetTester tester, double height) {
  tester.view.physicalSize =
      Size(kRunnerWindowSize.width, height) * tester.view.devicePixelRatio;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a teacher rail fits the runner window and a laptop window with '
      'every entry tappable where it is, and scrolls instead of overflowing '
      'when the window is shorter than it', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    expect(find.text('Hi Yvan,'), findsOneWidget);

    // 1280x720, the window the runner creates. Every entry is up, and none
    // of them is behind a scroll.
    for (final entry in _entries) {
      expect(find.byTooltip(entry), findsOneWidget, reason: entry);
    }
    expect(
      _railScroll(tester).maxScrollExtent,
      0,
      reason:
          'the rail is ${_railScroll(tester).maxScrollExtent} px taller than '
          'the runner window, so an entry is only reachable by scrolling',
    );
    // With a whole entry to spare, so the next feature that wants one does
    // not land on the edge the way #148 did.
    expect(
      _slackUnderLast(tester),
      greaterThanOrEqualTo(sidebarItemExtent),
      reason:
          'the rail has ${_slackUnderLast(tester)} px left at 720 px, less '
          'than the $sidebarItemExtent px an entry takes',
    );

    // Tapped where it is, with no `ensureVisible` — the way every other flow
    // taps it.
    await tester.tap(find.byTooltip('Reports'));
    await pumpUntilFound(tester, find.byType(ReportsPage));

    // The laptop: before this fix the rail was already too tall for it.
    _resize(tester, _laptopHeight);
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the shell overflowed a ${_laptopHeight.toInt()} px window',
    );
    expect(_railScroll(tester).maxScrollExtent, 0);
    for (final entry in _entries) {
      expect(find.byTooltip(entry), findsOneWidget, reason: entry);
    }
    // The pinned strip is where it belongs: at the bottom of the rail.
    final rail = tester.getRect(find.byType(Sidebar));
    expect(
      tester.getRect(find.byTooltip('Sign out')).bottom,
      lessThanOrEqualTo(rail.bottom),
    );
    expect(
      tester.getRect(find.byTooltip('Options')).top,
      greaterThan(tester.getRect(_destinations()).top),
    );

    // Half a screen: now the rail is taller than its room. Nothing clips —
    // the destinations scroll.
    _resize(tester, _shortHeight);
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the shell overflowed a ${_shortHeight.toInt()} px window',
    );
    expect(_railScroll(tester).maxScrollExtent, greaterThan(0));

    // Options and sign-out are outside the scroll view, so they are still
    // there and still work.
    final shortRail = tester.getRect(find.byType(Sidebar));
    expect(
      tester.getRect(find.byTooltip('Sign out')).bottom,
      lessThanOrEqualTo(shortRail.bottom),
    );
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    // And the entry that is now below the fold is reachable by scrolling to
    // it, which is all the safety net has to promise.
    await tester.ensureVisible(find.byTooltip('Reports'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reports'));
    await pumpUntilFound(tester, find.byType(ReportsPage));
    expect(find.byType(OptionsPage), findsNothing);
    expect(tester.takeException(), isNull);

    _resize(tester, kRunnerWindowSize.height);
    await tester.pump();
    await harness.dispose(tester);
  });
}
