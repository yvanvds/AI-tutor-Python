// End-to-end (#315): deleting a subgoal and undoing it gives the subgoal
// back with its concept marking.
//
// The teacher opens the subgoal "Print" on the Goals page; its "Concept goal"
// switch is on. The teacher deletes it — the doc is gone from `goals` — and
// taps Undo on the snackbar: the doc is back with `kind: 'concept'`, its
// lesson link and its learning objective, and the goal editor of "Print"
// shows the switch on again. The backup used to leave `kind` out, so the
// subgoal came back as an ordinary one and no longer fired the level-up
// screen.
//
// Real app, real navigation, real goals page and goal editor, real
// GoalsService polling the (in-memory) Cosmos containers.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goal_delete_undo.dart -d windows

import 'package:ai_tutor_python/features/goals/editor/goal_form.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(GoalForm), matching: finder);

  final concept = find.widgetWithText(SwitchListTile, 'Concept goal');

  /// Opens the goal editor on "Print" and scrolls to its concept switch.
  Future<void> openPrint(WidgetTester tester) async {
    await pumpUntilFound(tester, find.text('Print'));
    await tester.tap(find.text('Print').first);
    await pumpUntil(
      tester,
      () =>
          find.byType(GoalForm).evaluate().isNotEmpty &&
          tester.widget<GoalForm>(find.byType(GoalForm)).goal.id == 's1',
      reason: 'the goal editor never opened on "Print"',
    );
    await tester.scrollUntilVisible(
      concept,
      120,
      // The goal form's own list comes first, before a text field's.
      scrollable: find
          .descendant(
            of: find.byType(GoalForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  testWidgets('the teacher deletes a concept subgoal and undoes it: the '
      'subgoal is back in `goals` with its concept marking, and the goal '
      'editor shows the switch on', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final goals = harness.cosmos['goals'];
    goals.upsert({...goals.read('s1')!, 'kind': 'concept'});

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await openPrint(tester);
    expect(tester.widget<SwitchListTile>(concept).value, isTrue);

    // Delete, and confirm.
    await tester.tap(inForm(find.byTooltip('Delete')));
    await pumpUntilFound(tester, find.text('Delete "Print"?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpUntilFound(tester, find.text('Deleted "Print".'));
    expect(goals['s1'], isNull);
    expect(goals['s2'], isNotNull, reason: 'the sibling is not touched');

    // Undo.
    await tester.tap(find.text('Undo'));
    await pumpUntil(
      tester,
      () => goals['s1'] != null,
      reason: 'Undo never wrote the subgoal back',
    );
    final restored = goals.read('s1')!;
    expect(restored['kind'], 'concept');
    expect(restored['title'], 'Print');
    expect(restored['parentId'], 'r1');
    expect(restored['contentId'], 's1');
    expect((restored['objectives'] as List).single['id'], 'lo-print');

    // The teacher sees the marking again.
    await openPrint(tester);
    expect(tester.widget<SwitchListTile>(concept).value, isTrue);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
