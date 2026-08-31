// End-to-end (#28, fixing #68): a teacher opens the Goals editor and the
// selected root row is actually highlighted.
//
// Why this has to run against the real app rather than the widget test next
// to it: the bug was not in a row or in a pane, it was in how the *page*
// composes them. `RootRow` asks for a `selectedTileColor`, and `ListTile`
// paints that — and every ink splash — into the nearest `Material` above it.
// The page's background used to be a coloured `Container`, i.e. a
// `ColoredBox`, which is painted in front of that Material and hid both. The
// pane test mounts the panes into a bare `Scaffold` and so never sees it; only
// booting the shell and navigating to the section renders the composition a
// teacher gets, which is where Flutter threw
// `ListTile background color or ink splashes may be invisible.` once per row
// per build.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goals_row_highlight.dart -d windows

import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/goals/root_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/ink_surface.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Goals: the selected root row can paint its highlight', (
    tester,
  ) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));

    // The seeded curriculum, as the editor lays it out: the root on the left,
    // its subgoals in the middle pane once the root has been auto-selected.
    await pumpUntilFound(tester, find.text('Basics'));
    await pumpUntilFound(tester, find.text('Print'));

    final selectedTile = find
        .descendant(
          of: find.byWidgetPredicate((w) => w is RootRow && w.selected),
          matching: find.byType(ListTile),
        )
        .first;
    await pumpUntilFound(tester, selectedTile);

    // The highlight is the feature: it must still be asked for…
    final tile = tester.widget<ListTile>(selectedTile);
    expect(tile.selected, isTrue);
    expect(tile.selectedTileColor, isNotNull);
    // …and nothing may stand between the row and the surface it paints on.
    // (Before the fix the app also threw the framework assertion here, once
    // per row per build, which fails this test on its own.)
    expect(
      firstSurfaceAbove(tester, selectedTile),
      isA<Material>(),
      reason:
          'an opaque box sits between the row and its Material, so the '
          'selected-row highlight is painted and then covered',
    );

    await harness.dispose(tester);
  });
}
