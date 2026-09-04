// Issue #115 — the Uitleg footer pages through theory the student has
// already seen. "Previous" walks back over the earlier non-optional sibling
// subgoals that carry a lesson; "Next" only exists once they have paged back
// and walks forward again, disappearing on the newest page. Paging is
// view-local: the tutor's active subgoal never moves.
//
// Mounts the real `ExplainView` over the real `GoalsService` /
// `ContentService` on an in-memory Cosmos, with the WebView platform
// replaced by the in-memory fake. The end-to-end version of this flow lives
// in `integration_test/flows/explain_paging.dart`.

import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_lesson_code_runner.dart';
import '../../helpers/fake_webview_platform.dart';
import '../../helpers/in_memory_cosmos.dart';

Map<String, dynamic> _goalDoc({
  required String id,
  required String title,
  String? parentId,
  int order = 1000,
  String? contentId,
  bool optional = false,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': optional,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': contentId,
  'moduleId': 'python-basics',
};

Map<String, dynamic> _contentDoc(String id, String body) => {
  'id': id,
  'type': 'content',
  'title': id,
  'body': body,
};

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

void main() {
  late FakeWebViewPlatform webviews;
  late InMemoryCosmos goals;
  late InMemoryCosmos content;

  final root = Goal(id: 'r1', title: 'Basics', order: 1000);

  /// s1 (seen) — s2 (optional, skipped) — s3 (active) — s4 (not yet reached).
  final active = Goal(
    id: 's3',
    title: 'Variables',
    parentId: 'r1',
    order: 3000,
    contentId: 'c3',
  );

  setUp(() {
    webviews = FakeWebViewPlatform.install();
    goals = InMemoryCosmos([
      _goalDoc(id: 'r1', title: 'Basics'),
      _goalDoc(
        id: 's1',
        title: 'Print',
        parentId: 'r1',
        order: 1000,
        contentId: 'c1',
      ),
      _goalDoc(
        id: 's2',
        title: 'Side quest',
        parentId: 'r1',
        order: 2000,
        contentId: 'c2',
        optional: true,
      ),
      _goalDoc(
        id: 's3',
        title: 'Variables',
        parentId: 'r1',
        order: 3000,
        contentId: 'c3',
      ),
      _goalDoc(
        id: 's4',
        title: 'Loops',
        parentId: 'r1',
        order: 4000,
        contentId: 'c4',
      ),
    ]);
    content = InMemoryCosmos([
      _contentDoc('c1', '<p>lesson-one</p>'),
      _contentDoc('c2', '<p>lesson-optional</p>'),
      _contentDoc('c3', '<p>lesson-three</p>'),
      _contentDoc('c4', '<p>lesson-four</p>'),
    ]);
  });

  Widget app(Goal child) => ProviderScope(
    overrides: [
      goalSelectionProvider.overrideWith(() => _PresetSelection(root, child)),
      goalsServiceProvider.overrideWithValue(
        GoalsService(container: goals.container),
      ),
      contentServiceProvider.overrideWith(
        () => ContentService(container: content.container),
      ),
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ExplainView()),
    ),
  );

  Future<void> mount(WidgetTester tester, {Goal? child}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(child ?? active));
    // Content poll, sibling poll, stylesheet asset load, channel
    // registration, page load.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> settlePage(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  String shownLesson() => webviews.controllers.single.currentHtml;

  Color labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  bool enabled(WidgetTester tester, String label) =>
      labelColor(tester, label) == AppColors.fgMute;

  group('explain footer paging', () {
    testWidgets('the newest page offers Previous but no Next', (tester) async {
      await mount(tester);

      expect(shownLesson(), contains('lesson-three'));
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);
      expect(enabled(tester, 'Previous'), isTrue);
      expect(find.text('Next'), findsNothing);

      await unmount(tester);
    });

    // #116: the caption used to read a hard-coded "+10 XP on completion".
    // The shell awards `kXpPerSubgoal` for finishing a subgoal and nothing
    // for an explain page, so the caption now names that number — and only
    // on the page whose XP is still to be earned.
    testWidgets('the XP caption names what the subgoal is actually worth', (
      tester,
    ) async {
      await mount(tester);

      expect(kXpPerSubgoal, 100);
      expect(find.text('+100 XP on completion'), findsOneWidget);
      expect(find.textContaining('+10 XP'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a page the student paged back to promises no XP', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text('+100 XP on completion'), findsOneWidget);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);

      // "Print" is finished; its XP is already in the pill.
      expect(shownLesson(), contains('lesson-one'));
      expect(find.textContaining('XP on completion'), findsNothing);

      // Back on the newest page it is there again.
      await tester.tap(find.text('Next'));
      await settlePage(tester);
      expect(find.text('+100 XP on completion'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('Previous opens the previous seen lesson and reveals Next; '
        'optional subgoals are skipped', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);

      // s2 is optional, so the page before "Variables" is "Print".
      expect(shownLesson(), contains('lesson-one'));
      expect(shownLesson(), isNot(contains('lesson-optional')));
      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      // Nothing older than the first lesson.
      expect(enabled(tester, 'Previous'), isFalse);

      await unmount(tester);
    });

    testWidgets('Next returns to the newest page and disappears again', (
      tester,
    ) async {
      await mount(tester);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);
      expect(shownLesson(), contains('lesson-one'));

      await tester.tap(find.text('Next'));
      await settlePage(tester);

      expect(shownLesson(), contains('lesson-three'));
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('Next'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a disabled Previous is inert on the oldest lesson', (
      tester,
    ) async {
      await mount(tester);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);
      expect(find.text('1 / 4'), findsOneWidget);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);

      expect(shownLesson(), contains('lesson-one'));
      expect(find.text('1 / 4'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('paging never moves the subgoal the tutor works against', (
      tester,
    ) async {
      await mount(tester);
      final element = tester.element(find.byType(ExplainView));
      final container = ProviderScope.containerOf(element);
      String? activeId() =>
          container.read(goalSelectionProvider).activeChildGoal?.id;

      expect(activeId(), 's3');
      await tester.tap(find.text('Previous'));
      await settlePage(tester);
      expect(activeId(), 's3');

      await tester.tap(find.text('Next'));
      await settlePage(tester);
      expect(activeId(), 's3');

      await unmount(tester);
    });

    testWidgets('the first lesson of the root has nothing to page back to', (
      tester,
    ) async {
      final first = Goal(
        id: 's1',
        title: 'Print',
        parentId: 'r1',
        order: 1000,
        contentId: 'c1',
      );
      await mount(tester, child: first);

      expect(shownLesson(), contains('lesson-one'));
      expect(find.text('1 / 4'), findsOneWidget);
      expect(enabled(tester, 'Previous'), isFalse);
      expect(find.text('Next'), findsNothing);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);
      expect(shownLesson(), contains('lesson-one'));

      await unmount(tester);
    });
  });
}
