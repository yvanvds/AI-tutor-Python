// Issue #4 — the Lesinhoud page must surface content docs orphaned by a goal
// re-import (Replace mode with new subgoal ids deletes the old subgoals but
// leaves their content docs in Cosmos) and let the teacher reassign them to a
// subgoal.
//
// This mounts the real page over the real GoalsService / ContentService /
// ModuleService, each backed by an in-memory Cosmos fake, so the flow is
// exercised end-to-end from the tree row through the dialog to the writes.
// The polling streams are real too: `pump(6s)` lets the next poll tick so
// the assertions about the tree reflect what a re-fetch would show.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo.

import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _poll = Duration(seconds: 6);

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? parentId,
  int order = 1000,
  String? contentId,
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
  'contentId': contentId,
  'moduleId': 'python-basics',
};

Map<String, dynamic> _content(String id, String title, String body) => {
  'id': id,
  'type': 'content',
  'title': title,
  'body': body,
};

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late InMemoryCosmos modules;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Loops'),
      _goal(id: 's-new', title: 'For loops', parentId: 'r1', order: 1000),
      _goal(
        id: 's-linked',
        title: 'While loops',
        parentId: 'r1',
        order: 2000,
        contentId: 's-linked',
      ),
    ]);
    content = InMemoryCosmos([
      // Left behind by a Replace import that renamed 's-old' -> 's-new'.
      _content('s-old', 'For loops lesson', '<p>for</p>'),
      _content('s-linked', 'While loops lesson', '<p>while</p>'),
    ]);
    modules = InMemoryCosmos([
      {
        'id': 'python-basics',
        'type': 'module',
        'title': 'Python basics',
        'order': 0,
      },
    ]);
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      goalsServiceProvider.overrideWithValue(
        GoalsService(container: goals.container),
      ),
      contentServiceProvider.overrideWith(
        () => ContentService(container: content.container),
      ),
      moduleServiceProvider.overrideWith(
        () => ModuleService(container: modules.container),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: LessonContentPage()),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    // Bootstrap (ensureDefaultModule + backfill) then first poll.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('orphaned content appears in its own tree section', (
    tester,
  ) async {
    await mount(tester);

    // Section headers render upper-cased, like the module headers.
    expect(find.text('ORPHANED LESSON CONTENT'), findsOneWidget);
    expect(find.text('For loops lesson'), findsOneWidget);
    // The linked doc is not an orphan; it shows under its subgoal only.
    expect(find.text('While loops lesson'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('tapping an orphan and picking a subgoal moves the doc and '
      'links the goal', (tester) async {
    await mount(tester);

    await tester.tap(find.text('For loops lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Reassign lesson content'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'For loops'));
    await tester.pumpAndSettle();

    // Writes: new doc under the target id, orphan gone, goal linked.
    expect(content['s-new'], isNotNull);
    expect(content['s-new']!['body'], '<p>for</p>');
    expect(content['s-new']!['title'], 'For loops lesson');
    expect(content['s-old'], isNull);
    expect(goals['s-new']!['contentId'], 's-new');
    expect(find.text('Lesson content linked to "For loops".'), findsOneWidget);

    // After the next goals poll the tree reflects the link: no orphan
    // section, and the subgoal row shows the lesson title.
    await tester.pump(_poll);
    await tester.pump();
    expect(find.text('ORPHANED LESSON CONTENT'), findsNothing);
    expect(find.text('For loops lesson'), findsOneWidget);
    expect(find.text('(no lesson content)'), findsNothing);

    await unmount(tester);
  });

  testWidgets('reassigning onto a subgoal that already has content asks '
      'before overwriting', (tester) async {
    await mount(tester);

    await tester.tap(find.text('For loops lesson'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'While loops'));
    await tester.pumpAndSettle();

    expect(find.text('Replace existing lesson content?'), findsOneWidget);

    // Cancel keeps everything as it was.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(content['s-old'], isNotNull);
    expect(content['s-linked']!['body'], '<p>while</p>');

    // Confirm replaces.
    await tester.tap(find.text('For loops lesson'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'While loops'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await tester.pumpAndSettle();

    expect(content['s-old'], isNull);
    expect(content['s-linked']!['body'], '<p>for</p>');
    expect(goals['s-linked']!['contentId'], 's-linked');

    await unmount(tester);
  });
}
