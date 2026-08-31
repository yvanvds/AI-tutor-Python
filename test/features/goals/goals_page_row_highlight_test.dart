// Issue #68 — `ListTile background color or ink splashes may be invisible.`
//
// The goals page painted its background with a coloured `Container`, i.e. a
// `ColoredBox`. `ListTile` paints its tile colour and ink splashes into the
// nearest `Material` *above* it, so that ColoredBox sat in front of them and
// hid both: the selected root row asked for `selectedTileColor` and rendered
// exactly like every other row, and Flutter reported the assertion once per
// row per build (39 of them in one captured window).
//
// The existing pane test (`goal_panes_reorder_test.dart`) cannot catch this:
// it mounts `RootPane` / `ChildPane` straight into a bare `Scaffold`, whose
// own Material is then the nearest one. Only the page's real composition
// reproduces it, which is what this mounts.
//
// The end-to-end half — a teacher opening Goals in the real shell — lives in
// `integration_test/flows/goals_row_highlight.dart`.

import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/goals/root_row.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

Map<String, dynamic> _goal({
  required String id,
  required String title,
  required int order,
  String? parentId,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': null,
  'moduleId': 'python-basics',
};

/// Walks up from [tile] the way `ListTile` does when it works out where its
/// background and ink will land: the first ancestor that is either a
/// `Material` (the surface it paints on) or an opaque box (which would be
/// painted *over* that surface and hide it).
Widget? firstSurfaceAbove(WidgetTester tester, Finder tile) {
  Widget? found;
  tester.element(tile).visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Material) {
      found = w;
      return false;
    }
    final Color? color = switch (w) {
      ColoredBox(:final Color color) => color,
      DecoratedBox(decoration: BoxDecoration(:final Color? color)) => color,
      _ => null,
    };
    if (color != null && color.a > 0) {
      found = w;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  testWidgets('the selected root row paints its highlight on a Material, not '
      'behind the page background', (tester) async {
    final goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Variables', order: 1000),
      _goal(id: 'r2', title: 'Loops', order: 2000),
      _goal(id: 'c1', title: 'Assignment', order: 1000, parentId: 'r1'),
    ]);
    final container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(const Scaffold(body: GoalsPage())),
      ),
    );
    // First roots poll, the microtask that selects the first root, then the
    // first children poll for it.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Before the fix this was the framework assertion, thrown once per row.
    expect(
      tester.takeException(),
      isNull,
      reason: 'a goals-page row cannot paint its tile colour or ink',
    );

    final selectedTile = find
        .descendant(
          of: find.byWidgetPredicate((w) => w is RootRow && w.selected),
          matching: find.byType(ListTile),
        )
        .first;
    expect(selectedTile, findsOneWidget);

    // The highlight is the feature: it must still be asked for…
    final tile = tester.widget<ListTile>(selectedTile);
    expect(tile.selected, isTrue);
    expect(tile.selectedTileColor, isNotNull);
    // …and nothing may stand between the row and the surface it paints on.
    expect(
      firstSurfaceAbove(tester, selectedTile),
      isA<Material>(),
      reason:
          'an opaque box sits between the row and its Material, so the '
          'selected-row highlight is painted and then covered',
    );

    // Unmounting cancels the panes' polling timers.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
