// Issue #21 — teaching tips in the goal editor were rendered as pills, which
// overflowed on long text and could only be deleted, never edited in place.
// The editor now lists tips as wrapping rows with edit / delete actions and an
// inline Save / Cancel edit mode.
//
// This mounts the real EditGoalPanel (the 420px side panel of the goals page)
// over the real GoalsService backed by an in-memory Cosmos fake, with the
// editor selection set the way a click on a subgoal row sets it, so the
// assertions cover the composed layout and the writes end-to-end.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo.

import 'package:ai_tutor_python/features/goals/editor/edit_goal_panel.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

const _longTip =
    'Start with a concrete example of a counter that goes wrong before you '
    'introduce the loop variable; students who see the off-by-one bug first '
    'remember why range() stops one short.';
const _shortTip = 'Mention the underscore convention.';

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? parentId,
  List<String> teachingTips = const [],
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': 1000,
  'optional': false,
  'teachingTips': teachingTips,
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': null,
  'moduleId': 'python-basics',
};

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late ProviderContainer container;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Loops'),
      _goal(
        id: 's1',
        title: 'For loops',
        parentId: 'r1',
        teachingTips: const [_longTip, _shortTip],
      ),
    ]);
    content = InMemoryCosmos();
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        contentServiceProvider.overrideWith(
          () => ContentService(container: content.container),
        ),
      ],
    );
  });

  List<String> storedTips() => List<String>.from(goals['s1']!['teachingTips']);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    container
        .read(goalSelectionProvider.notifier)
        .setEditorSelectedGoal(Goal.fromCosmos(goals['s1']!));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(
          const Scaffold(
            // Same slot the goals page gives the panel.
            body: Row(children: [SizedBox(width: 720, child: EditGoalPanel())]),
          ),
        ),
      ),
    );
    // Panel open animation + first goal poll.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  }

  // Unmounting cancels the goal poll; disposing the container cancels the
  // content poll ContentService started when the form watched it.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  Finder addField() =>
      find.widgetWithText(TextField, 'Type a teaching tip and hit Enter');

  Finder tipRowButton(String tooltip, {required String forTip}) => find
      .descendant(
        of: find.ancestor(of: find.text(forTip), matching: find.byType(Row)),
        matching: find.byTooltip(tooltip),
      )
      .first;

  testWidgets('a long tip is shown in full, wrapped over several lines', (
    tester,
  ) async {
    await mount(tester);

    expect(find.text(_longTip), findsOneWidget);
    expect(find.text(_shortTip), findsOneWidget);

    final longSize = tester.getSize(find.text(_longTip));
    final shortSize = tester.getSize(find.text(_shortTip));
    expect(longSize.height, greaterThan(shortSize.height * 2));
    // Both tips use the full row width, not a pill sized to their content.
    expect(longSize.width, shortSize.width);

    await unmount(tester);
  });

  testWidgets('editing a tip in place starts from the original text and '
      'saves the change', (tester) async {
    await mount(tester);

    await tester.tap(tipRowButton('Edit tip', forTip: _longTip));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, _longTip);
    expect(field, findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.enterText(field, '$_longTip Then show the fixed version.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(storedTips(), ['$_longTip Then show the fixed version.', _shortTip]);
    // Edit mode is gone: title, description and the add field remain.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Save'), findsNothing);
    expect(find.text('$_longTip Then show the fixed version.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('cancelling an edit keeps the original tip', (tester) async {
    await mount(tester);

    await tester.tap(tipRowButton('Edit tip', forTip: _shortTip));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, _shortTip),
      'something else',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(storedTips(), [_longTip, _shortTip]);
    expect(find.text(_shortTip), findsOneWidget);
    expect(find.text('something else'), findsNothing);

    await unmount(tester);
  });

  testWidgets('adding with Enter appends and deleting removes a tip', (
    tester,
  ) async {
    await mount(tester);

    await tester.enterText(
      addField(),
      '  Let them predict the output first.  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(storedTips(), [
      _longTip,
      _shortTip,
      'Let them predict the output first.',
    ]);
    expect(find.text('Let them predict the output first.'), findsOneWidget);

    await tester.tap(tipRowButton('Delete tip', forTip: _shortTip));
    await tester.pumpAndSettle();

    expect(storedTips(), [_longTip, 'Let them predict the output first.']);
    expect(find.text(_shortTip), findsNothing);

    await unmount(tester);
  });
}
