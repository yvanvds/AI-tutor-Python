// Issues #29 / #30 — `ReorderableListView.onReorder` is deprecated since
// Flutter 3.44 in favour of `onReorderItem`, whose `newIndex` is already
// adjusted for the item removed at `oldIndex`. The panes used to correct the
// index themselves; after the migration that correction must be gone, or a
// downward drag lands one slot short.
//
// This mounts the real RootPane and ChildPane side by side (the same Row the
// goals page builds) over the real GoalsService backed by an in-memory Cosmos
// fake, and drags the row handles the way a user does, asserting on the order
// that gets written back and on the order the panes render after the next
// poll.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/goals/child_pane.dart';
import 'package:ai_tutor_python/features/goals/root_pane.dart';
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

void main() {
  late InMemoryCosmos goals;
  late ProviderContainer container;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Variables', order: 1000),
      _goal(id: 'r2', title: 'Loops', order: 2000),
      _goal(id: 'r3', title: 'Functions', order: 3000),
      _goal(id: 'c1', title: 'Assignment', order: 1000, parentId: 'r1'),
      _goal(id: 'c2', title: 'Naming', order: 2000, parentId: 'r1'),
      _goal(id: 'c3', title: 'Types', order: 3000, parentId: 'r1'),
    ]);
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
      ],
    );
  });

  /// Ids under [parentId] in the order the service will serve them.
  List<String> storedOrder(String? parentId) {
    final docs =
        goals.docs.values.where((d) => d['parentId'] == parentId).toList()
          ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return docs.map((d) => d['id'] as String).toList();
  }

  /// Titles as rendered top-to-bottom inside [pane].
  List<String> renderedTitles(WidgetTester tester, Finder pane) {
    final tiles = find.descendant(of: pane, matching: find.byType(ListTile));
    final entries = tester.widgetList<ListTile>(tiles).map((t) {
      final title = (t.title as Text).data!;
      final dy = tester.getTopLeft(find.byWidget(t)).dy;
      return (title, dy);
    }).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    return entries.map((e) => e.$1).toList();
  }

  Finder handleOf(String title) => find
      .descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Icons.drag_handle),
      )
      .first;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final svc = container.read(goalsServiceProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(
          Scaffold(
            // Same slots the goals page gives the two panes.
            body: Row(
              children: [
                Expanded(child: RootPane(rootsAsync: svc.streamRoots!)),
                const VerticalDivider(width: 1),
                const Expanded(child: ChildPane()),
              ],
            ),
          ),
        ),
      ),
    );
    // First root poll, the microtask that selects the first root, then the
    // first children poll for that root.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  // Unmounting cancels both polling streams' timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  /// Drags [title]'s handle by [dy] and lets the drop animation finish.
  Future<void> dragRow(WidgetTester tester, String title, double dy) async {
    final gesture = await tester.startGesture(
      tester.getCenter(handleOf(title)),
    );
    await tester.pump();
    // Move in small steps so the list gets to open the gap under the pointer
    // the way it does for a real drag.
    const steps = 20;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a root goal down lands it below the row it passed', (
    tester,
  ) async {
    await mount(tester);
    final rootPane = find.byType(RootPane);
    expect(renderedTitles(tester, rootPane), [
      'Variables',
      'Loops',
      'Functions',
    ]);

    final rowHeight = tester
        .getSize(
          find.ancestor(
            of: find.text('Loops'),
            matching: find.byType(ListTile),
          ),
        )
        .height;
    await dragRow(tester, 'Variables', rowHeight * 1.2);

    expect(storedOrder(null), ['r2', 'r1', 'r3']);
    expect(find.text('Reordered "Variables".'), findsOneWidget);

    await tester.pump(kCosmosPollInterval);
    await tester.pump();
    expect(renderedTitles(tester, rootPane), [
      'Loops',
      'Variables',
      'Functions',
    ]);

    await unmount(tester);
  });

  testWidgets('dragging a root goal up lands it above the row it passed', (
    tester,
  ) async {
    await mount(tester);

    final rowHeight = tester
        .getSize(
          find.ancestor(
            of: find.text('Loops'),
            matching: find.byType(ListTile),
          ),
        )
        .height;
    await dragRow(tester, 'Functions', -rowHeight * 2.5);

    expect(storedOrder(null), ['r3', 'r1', 'r2']);

    await tester.pump(kCosmosPollInterval);
    await tester.pump();
    expect(renderedTitles(tester, find.byType(RootPane)), [
      'Functions',
      'Variables',
      'Loops',
    ]);

    await unmount(tester);
  });

  testWidgets('dragging a subgoal down reorders it under its root, and Undo '
      'restores the previous order', (tester) async {
    await mount(tester);
    final childPane = find.byType(ChildPane);
    expect(renderedTitles(tester, childPane), [
      'Assignment',
      'Naming',
      'Types',
    ]);

    final rowHeight = tester
        .getSize(
          find.ancestor(
            of: find.text('Naming'),
            matching: find.byType(ListTile),
          ),
        )
        .height;
    await dragRow(tester, 'Assignment', rowHeight * 2.5);

    expect(storedOrder('r1'), ['c2', 'c3', 'c1']);
    // Roots untouched.
    expect(storedOrder(null), ['r1', 'r2', 'r3']);
    expect(find.text('Reordered "Assignment".'), findsOneWidget);

    await tester.pump(kCosmosPollInterval);
    await tester.pump();
    expect(renderedTitles(tester, childPane), [
      'Naming',
      'Types',
      'Assignment',
    ]);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(storedOrder('r1'), ['c1', 'c2', 'c3']);

    await tester.pump(kCosmosPollInterval);
    await tester.pump();
    expect(renderedTitles(tester, childPane), [
      'Assignment',
      'Naming',
      'Types',
    ]);

    await unmount(tester);
  });
}
