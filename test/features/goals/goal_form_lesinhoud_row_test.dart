// Issue #208 — the subgoal editor's Lesinhoud row says which translations
// the lesson has, and marks one stale when the Dutch lesson changed after it
// was translated (its `sourceHash` no longer matches).
//
// Mounts the real EditGoalPanel (the goals page's side panel) over the real
// GoalsService / ContentService / TranslationService on in-memory Cosmos,
// with the editor selection set the way a click on a subgoal row sets it.

import 'package:ai_tutor_python/features/goals/editor/edit_goal_panel.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

final _lesson = Content(id: 's1', title: 'Printen', body: '<p>Zo.</p>');

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? parentId,
  String? contentId,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': 1000,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': contentId,
  'moduleId': 'python-basics',
};

Map<String, dynamic> _english(String sourceHash) => Translation.content(
  language: 'en',
  contentId: 's1',
  title: 'Printing',
  body: '<p>Like this.</p>',
  sourceHash: sourceHash,
).toMap();

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late InMemoryCosmos translations;
  late ProviderContainer container;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Basics'),
      _goal(id: 's1', title: 'Print', parentId: 'r1', contentId: 's1'),
    ]);
    content = InMemoryCosmos([
      {..._lesson.toMap(), 'type': 'content'},
    ]);
    translations = InMemoryCosmos.partitioned('language');
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        contentServiceProvider.overrideWith(
          () => ContentService(container: content.container),
        ),
        translationServiceProvider.overrideWithValue(
          TranslationService(container: translations.container),
        ),
      ],
    );
  });

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
            body: Row(children: [SizedBox(width: 720, child: EditGoalPanel())]),
          ),
        ),
      ),
    );
    // Panel animation, then the goal, content and translation polls.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  Finder badge(TranslationStatus status) =>
      find.byKey(Key('translation-status-en-${status.name}'));

  testWidgets('no translation: the row shows the Dutch lesson only', (
    tester,
  ) async {
    await mount(tester);

    expect(find.text('Printen'), findsOneWidget);
    expect(badge(TranslationStatus.current), findsNothing);
    expect(badge(TranslationStatus.stale), findsNothing);

    await unmount(tester);
  });

  testWidgets('a translation made from the Dutch lesson as it is shows as '
      'up to date', (tester) async {
    translations.upsert(
      _english(contentSourceHash(_lesson)),
      partitionKey: 'en',
    );
    await mount(tester);

    expect(badge(TranslationStatus.current), findsOneWidget);
    expect(find.byTooltip('English translation: up to date'), findsOneWidget);
    // In the Lesinhoud row, next to its Edit handoff.
    expect(
      tester.getCenter(badge(TranslationStatus.current)).dy,
      moreOrLessEquals(tester.getCenter(find.text('Edit')).dy, epsilon: 12),
    );

    await unmount(tester);
  });

  testWidgets('the translation turns stale when the Dutch lesson changes', (
    tester,
  ) async {
    translations.upsert(
      _english(contentSourceHash(_lesson)),
      partitionKey: 'en',
    );
    await mount(tester);
    expect(badge(TranslationStatus.current), findsOneWidget);

    content.upsert({...content['s1']!, 'body': '<p>Anders.</p>'});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();

    expect(badge(TranslationStatus.current), findsNothing);
    expect(badge(TranslationStatus.stale), findsOneWidget);
    expect(
      find.byTooltip(
        'English translation: outdated, the Dutch text changed after it was '
        'translated',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });
}
