// End-to-end (#252): on the learning path the subgoal tiles of a goal wrap
// onto the next line instead of running off the card in a row that only
// scrolls by touch. A goal with six subgoals shows every tile whole, inside
// its card and inside the window, both in the window the runner creates and
// in a narrow one; each tile opens its learning objectives, under all of
// the tiles. Nothing to scroll sideways, so nothing a mouse cannot reach.
//
// Real app, real navigation, real Leerpad with the real font, over the
// (in-memory) Cosmos containers. No model: nothing here asks one.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/leerpad_subgoal_wrap.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_objectives_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// The seeded "Basics" has "Print" and "Variables"; these make six.
const List<String> kMore = ['Input', 'Numbers', 'Text', 'Lists'];

String statementOf(String goalId) => switch (goalId) {
  's1' => 'Use print() to show text',
  's2' => 'Assign a value to a name',
  _ => 'Je kan stap $goalId zetten.',
};

List<Map<String, dynamic>> curriculum() => [
  for (var i = 0; i < kMore.length; i++)
    goalDoc(
      id: 's${i + 3}',
      title: kMore[i],
      parentId: 'r1',
      order: 3000 + 1000 * i,
      objectives: [objective('lo-s${i + 3}', statementOf('s${i + 3}'))],
    ),
];

const List<String> kSubgoals = ['s1', 's2', 's3', 's4', 's5', 's6'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder card(String rootId) =>
      find.byWidgetPredicate((w) => w is LeerpadCard && w.root.id == rootId);
  Finder chip(String goalId) => find.byWidgetPredicate(
    (w) => w is LeerpadChildChip && w.goal.id == goalId,
  );
  final panel = find.byType(LeerpadObjectivesPanel);

  bool inside(Rect outer, Rect inner) =>
      inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;

  Rect window(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  /// Every tile whole in the card and in the window, on more than one line;
  /// each one opens its own objectives under the lowest tile.
  Future<void> everyTileInReach(WidgetTester tester, String where) async {
    expect(
      find.descendant(of: card('r1'), matching: find.byType(Scrollable)),
      findsNothing,
      reason: where,
    );
    final cardRect = tester.getRect(card('r1'));
    final lines = <double>{};
    var lowest = 0.0;
    for (final id in kSubgoals) {
      final rect = tester.getRect(chip(id));
      expect(inside(cardRect, rect), isTrue, reason: '$where: $id at $rect');
      expect(inside(window(tester), rect), isTrue, reason: '$where: $id');
      lines.add(rect.top);
      if (rect.bottom > lowest) lowest = rect.bottom;
    }
    expect(lines.length, greaterThan(1), reason: where);

    for (final id in kSubgoals) {
      await tester.tap(chip(id));
      await pumpUntilFound(tester, find.text(statementOf(id)));
      expect(panel, findsOneWidget, reason: '$where: $id');
      expect(tester.getRect(panel).top, greaterThan(lowest), reason: id);
    }
    // The last one closes again.
    await tester.tap(chip(kSubgoals.last));
    await pumpUntilGone(tester, panel);
  }

  testWidgets('a goal with six subgoals shows every tile whole and opens '
      'each one, in the runner window and in a narrow one', (tester) async {
    final harness = AppHarness(extraDocs: {'goals': curriculum()});
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, chip('s6'));

    // 1280 px: the card is 760 wide, room for three tiles on a line.
    await everyTileInReach(tester, 'runner window');

    // A narrower window: the card shrinks with it, the tiles stay whole.
    // Not narrower than 860 px for now: under ~820 px the top bar's stat
    // strip overflows on its own (#258), whatever the Leerpad does.
    tester.view.physicalSize =
        Size(860, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
    await pumpUntil(
      tester,
      () => tester.getSize(card('r1')).width < 760,
      reason: 'the card never narrowed with the window',
    );
    await everyTileInReach(tester, '860 px');

    await harness.dispose(tester);
  });
}
