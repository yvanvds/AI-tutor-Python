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

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
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

  List<Override> overrides(Goal child, {Goal? rootGoal}) => [
    goalSelectionProvider.overrideWith(
      () => _PresetSelection(rootGoal ?? root, child),
    ),
    goalsServiceProvider.overrideWithValue(
      GoalsService(container: goals.container),
    ),
    contentServiceProvider.overrideWith(
      () => ContentService(container: content.container),
    ),
    lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
    // The theory page reads lessons in the app language (#207): English,
    // with no translations.
    appLocaleProvider.overrideWithValue(const Locale('en')),
    translationServiceProvider.overrideWithValue(
      TranslationService(
        container: InMemoryCosmos.partitioned('language').container,
      ),
    ),
  ];

  Widget materialApp(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );

  Widget app(Goal child, {Goal? rootGoal}) => ProviderScope(
    overrides: overrides(child, rootGoal: rootGoal),
    child: materialApp(const ExplainView()),
  );

  Future<void> mount(
    WidgetTester tester, {
    Goal? child,
    Goal? rootGoal,
    double width = 1400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(child ?? active, rootGoal: rootGoal));
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

    testWidgets('the first lesson of the first goal has nothing to page back '
        'to', (tester) async {
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

  // #259: next to an open chat in a narrow window — or while the chat slides
  // shut after the window was made narrow — the lesson column is a few
  // hundred pixels wide, and the footer's row ran 243 px past it. Now the
  // footer shows the richest form of itself that fits: first the XP caption
  // goes, then the words on the paging buttons, then the words on "Try it
  // yourself", each word kept in its button's tooltip. The widths below are
  // for the test font, which is wider than the app's.
  group('explain footer in a narrow column', () {
    final footer = find.byKey(const Key('explain-footer'));

    /// Every part of the footer on screen lies inside the view.
    void expectInside(WidgetTester tester) {
      final view = tester.getRect(find.byType(ExplainView));
      final parts = find.descendant(
        of: footer,
        matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
      );
      expect(parts, findsWidgets);
      for (final part in parts.evaluate()) {
        final box = part.renderObject! as RenderBox;
        final r = box.localToGlobal(Offset.zero) & box.size;
        expect(
          r.left >= view.left && r.right <= view.right,
          isTrue,
          reason: '${part.widget} at $r, view $view',
        );
      }
      expect(tester.takeException(), isNull);
    }

    testWidgets('a wide column spells everything out', (tester) async {
      await mount(tester, width: 800);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('+100 XP on completion'), findsOneWidget);
      expect(find.text('Try it yourself'), findsOneWidget);
      expect(find.byTooltip('Previous'), findsNothing);
      expectInside(tester);
      await unmount(tester);
    });

    testWidgets('narrower, the XP caption goes first', (tester) async {
      await mount(tester, width: 560);
      expect(find.textContaining('XP on completion'), findsNothing);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Try it yourself'), findsOneWidget);
      expectInside(tester);
      await unmount(tester);
    });

    testWidgets('narrower still, the paging buttons keep their words in a '
        'tooltip, and still page', (tester) async {
      await mount(tester, width: 400);
      expect(find.text('Previous'), findsNothing);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.text('Try it yourself'), findsOneWidget);
      expectInside(tester);

      await tester.tap(find.byTooltip('Previous'));
      await settlePage(tester);
      expect(shownLesson(), contains('lesson-one'));
      expect(find.byTooltip('Next'), findsOneWidget);
      expectInside(tester);

      await tester.tap(find.byTooltip('Next'));
      await settlePage(tester);
      expect(shownLesson(), contains('lesson-three'));
      expect(find.byTooltip('Next'), findsNothing);

      await unmount(tester);
    });

    testWidgets('narrowest, Try it yourself is its arrow, and still opens '
        'practice', (tester) async {
      await mount(tester, width: 200);
      expect(find.text('Try it yourself'), findsNothing);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.byTooltip('Try it yourself'), findsOneWidget);
      expectInside(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExplainView)),
      );
      await tester.tap(find.byTooltip('Try it yourself'));
      await tester.pump();
      expect(container.read(modeProvider), SessionMode.practice);

      await unmount(tester);
    });

    testWidgets('a long goal title ends in an ellipsis before the counter', (
      tester,
    ) async {
      final longRoot = Goal(
        id: 'r1',
        title: 'Be able to write and understand very basic Python scripts',
        order: 1000,
      );
      await mount(tester, width: 400, rootGoal: longRoot);
      expect(tester.takeException(), isNull);
      final view = tester.getRect(find.byType(ExplainView));
      final counter = tester.getRect(find.text('3 / 4'));
      expect(counter.right, lessThanOrEqualTo(view.right));
      final pill = tester.getRect(find.text(longRoot.title.toUpperCase()));
      expect(pill.right, lessThan(counter.left));
      await unmount(tester);
    });
  });

  // #128: the sibling poll emits every 5 s whether or not the curriculum
  // changed, and the view used to `setState` on every emission — a full
  // rebuild down to the WebView, which on Windows blinked. Now an unchanged
  // poll is dropped, a changed one still lands, and neither reaches the
  // platform widget.
  group('sibling polls', () {
    Future<void> poll(WidgetTester tester) async {
      await tester.pump(kCosmosPollInterval);
      await tester.pump();
    }

    LessonHtmlView lesson(WidgetTester tester) =>
        tester.widget<LessonHtmlView>(find.byType(LessonHtmlView));

    testWidgets('an unchanged poll does not rebuild the view', (tester) async {
      await mount(tester);
      final before = lesson(tester);
      expect(webviews.widgetBuilds, 1);

      await poll(tester);
      await poll(tester);

      expect(
        lesson(tester),
        same(before),
        reason: 'a poll with the same siblings rebuilt the explain view',
      );
      expect(find.text('3 / 4'), findsOneWidget);
      expect(webviews.widgetsCreated, 1);
      expect(webviews.widgetBuilds, 1);
      expect(shownLesson(), contains('lesson-three'));

      await unmount(tester);
    });

    testWidgets('a changed poll still lands, without touching the platform '
        'widget', (tester) async {
      await mount(tester);
      final before = lesson(tester);

      // The teacher adds a subgoal after the active one.
      goals.docs['s5'] = _goalDoc(
        id: 's5',
        title: 'Functions',
        parentId: 'r1',
        order: 5000,
        contentId: 'c5',
      );
      await poll(tester);

      expect(lesson(tester), isNot(same(before)));
      expect(find.text('3 / 5'), findsOneWidget);
      expect(webviews.widgetsCreated, 1);
      expect(webviews.widgetBuilds, 1);
      // Same page, same document: nothing was reloaded.
      expect(webviews.controllers.single.loadedHtml, hasLength(1));

      await unmount(tester);
    });

    testWidgets('a sibling turning optional changes what Previous reaches', (
      tester,
    ) async {
      await mount(tester);
      expect(enabled(tester, 'Previous'), isTrue);

      // The only seen page, "Print", becomes a side quest.
      goals.docs['s1']!['optional'] = true;
      await poll(tester);

      expect(enabled(tester, 'Previous'), isFalse);
      expect(webviews.widgetBuilds, 1);

      await unmount(tester);
    });
  });

  // #132: the view publishes the page it shows, so a question typed in the
  // chat can be about it — the page paged back to, not the active
  // subgoal's, and nothing once the view is gone.
  group('the page on screen', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(ExplainView)));

    testWidgets('is the lesson of the active subgoal, then the one paged '
        'back to, then the newest again; nothing once the view is gone', (
      tester,
    ) async {
      // A container of the test's own, so it outlives the view.
      final container = ProviderContainer(overrides: overrides(active));
      String? viewed() => container.read(viewedContentIdProvider);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: materialApp(const ExplainView()),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(viewed(), 'c3');
      expect(webviews.widgetBuilds, 1);

      await tester.tap(find.text('Previous'));
      await settlePage(tester);
      expect(shownLesson(), contains('lesson-one'));
      expect(viewed(), 'c1');

      await tester.tap(find.text('Next'));
      await settlePage(tester);
      expect(viewed(), 'c3');
      // Publishing is not a rebuild of the WebView.
      expect(webviews.widgetsCreated, 1);
      expect(webviews.widgetBuilds, 1);

      // The view leaves the screen, the scope stays.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: materialApp(const SizedBox()),
        ),
      );
      await tester.pump();
      expect(viewed(), isNull, reason: 'the view left the screen');

      await unmount(tester);
      // Before the framework checks for pending timers: the content poll.
      container.dispose();
    });

    testWidgets('is nothing for a subgoal without a lesson', (tester) async {
      final bare = Goal(id: 's4', title: 'Loops', parentId: 'r1', order: 4000);
      goals.docs['s4']!['contentId'] = null;
      await mount(tester, child: bare);
      final container = containerOf(tester);

      expect(find.byType(LessonHtmlView), findsNothing);
      expect(container.read(viewedContentIdProvider), isNull);

      await unmount(tester);
    });
  });

  // #272: Previous used to stop at the first lesson of the active goal, so a
  // student on goal 5 could not look up how goal 2 explained something.
  // Now it goes on to the last lesson of the goal before it, and so on back
  // through every earlier goal in the Leerpad's order — started or not, a
  // goal without lessons skipped — and Next walks forward again. Still
  // view-local; the header and the chat belong to the page on screen.
  group('earlier goals', () {
    /// Basics (r1, above) — Setup (no lessons) — Strings, where the student
    /// is on "Methods" — Advanced, after it. By title "Advanced" would come
    /// first; the Leerpad goes by `order`.
    final strings = Goal(id: 'r2', title: 'Strings', order: 2000);
    final methods = Goal(
      id: 't2',
      title: 'Methods',
      parentId: 'r2',
      order: 2000,
      contentId: 'd2',
    );

    setUp(() {
      for (final doc in [
        _goalDoc(id: 'rx', title: 'Setup', order: 1500),
        _goalDoc(id: 'x1', title: 'Install', parentId: 'rx', order: 1000),
        _goalDoc(id: 'r2', title: 'Strings', order: 2000),
        _goalDoc(
          id: 't1',
          title: 'Slicing',
          parentId: 'r2',
          order: 1000,
          contentId: 'd1',
        ),
        _goalDoc(
          id: 't2',
          title: 'Methods',
          parentId: 'r2',
          order: 2000,
          contentId: 'd2',
        ),
        _goalDoc(id: 'r3', title: 'Advanced', order: 3000),
        _goalDoc(
          id: 'a1',
          title: 'Classes',
          parentId: 'r3',
          order: 1000,
          contentId: 'e1',
        ),
      ]) {
        goals.docs[doc['id'] as String] = doc;
      }
      for (final doc in [
        _contentDoc('d1', '<p>lesson-slicing</p>'),
        _contentDoc('d2', '<p>lesson-methods</p>'),
        _contentDoc('e1', '<p>lesson-classes</p>'),
        _contentDoc('x1', '<p>lesson-install</p>'),
      ]) {
        content.docs[doc['id'] as String] = doc;
      }
    });

    Future<void> mountOnMethods(WidgetTester tester) =>
        mount(tester, child: methods, rootGoal: strings);

    Future<void> previous(WidgetTester tester) async {
      await tester.tap(find.text('Previous'));
      await settlePage(tester);
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await settlePage(tester);
    }

    /// The page on screen: its lesson, and the header's goal and counter.
    void expectPage(String lesson, String goal, String counter) {
      expect(shownLesson(), contains(lesson));
      expect(find.text(goal), findsOneWidget);
      expect(find.text(counter), findsOneWidget);
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(ExplainView)));

    testWidgets('Previous on the first lesson of a goal goes on to the last '
        'lesson of the goal before it, past a goal without lessons, back to '
        'the first lesson of the first goal', (tester) async {
      await mountOnMethods(tester);
      expectPage('lesson-methods', 'STRINGS', '2 / 2');

      await previous(tester);
      expectPage('lesson-slicing', 'STRINGS', '1 / 2');
      expect(enabled(tester, 'Previous'), isTrue);

      // "Setup" has no lessons; the goal before it is "Basics".
      await previous(tester);
      expectPage('lesson-four', 'BASICS', '4 / 4');
      expect(find.text('STRINGS'), findsNothing);

      await previous(tester);
      expectPage('lesson-three', 'BASICS', '3 / 4');

      // "Side quest" is optional, so the page before "Variables" is "Print".
      await previous(tester);
      expectPage('lesson-one', 'BASICS', '1 / 4');
      expect(enabled(tester, 'Previous'), isFalse);
      expect(find.text('Next'), findsOneWidget);

      // Nothing before the first goal: "Advanced" comes after "Strings".
      await previous(tester);
      expectPage('lesson-one', 'BASICS', '1 / 4');

      await unmount(tester);
    });

    testWidgets('Next walks forward across goals back to the newest page, '
        'where the XP caption is back and Next is gone', (tester) async {
      await mountOnMethods(tester);
      for (var i = 0; i < 4; i++) {
        await previous(tester);
      }
      expectPage('lesson-one', 'BASICS', '1 / 4');
      expect(find.textContaining('XP on completion'), findsNothing);

      await next(tester);
      expectPage('lesson-three', 'BASICS', '3 / 4');
      await next(tester);
      expectPage('lesson-four', 'BASICS', '4 / 4');
      await next(tester);
      expectPage('lesson-slicing', 'STRINGS', '1 / 2');
      expect(find.textContaining('XP on completion'), findsNothing);

      await next(tester);
      expectPage('lesson-methods', 'STRINGS', '2 / 2');
      expect(find.text('Next'), findsNothing);
      expect(find.text('+100 XP on completion'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('paging into an earlier goal moves neither the goal nor the '
        'subgoal the tutor works against, and publishes the page on '
        'screen', (tester) async {
      await mountOnMethods(tester);
      final container = containerOf(tester);
      ({String? root, String? child}) target() {
        final s = container.read(goalSelectionProvider);
        return (root: s.activeRootGoal?.id, child: s.activeChildGoal?.id);
      }

      expect(container.read(viewedContentIdProvider), 'd2');

      await previous(tester);
      await previous(tester);
      expectPage('lesson-four', 'BASICS', '4 / 4');
      expect(target(), (root: 'r2', child: 't2'));
      expect(container.read(viewedContentIdProvider), 'c4');

      await next(tester);
      await next(tester);
      expect(target(), (root: 'r2', child: 't2'));
      expect(container.read(viewedContentIdProvider), 'd2');
      // Paging is not a rebuild of the WebView.
      expect(webviews.widgetsCreated, 1);
      expect(webviews.widgetBuilds, 1);

      await unmount(tester);
    });

    testWidgets('an unchanged poll of every goal does not rebuild the view; '
        'a lesson added to an earlier goal lands', (tester) async {
      await mountOnMethods(tester);
      final before = tester.widget<LessonHtmlView>(find.byType(LessonHtmlView));

      await tester.pump(kCosmosPollInterval);
      await tester.pump();
      await tester.pump(kCosmosPollInterval);
      await tester.pump();
      expect(
        tester.widget<LessonHtmlView>(find.byType(LessonHtmlView)),
        same(before),
        reason: 'a poll with the same curriculum rebuilt the explain view',
      );
      expect(webviews.widgetBuilds, 1);

      // The teacher writes a lesson for "Setup"'s only subgoal.
      goals.docs['x1']!['contentId'] = 'x1';
      await tester.pump(kCosmosPollInterval);
      await tester.pump();
      expect(webviews.widgetBuilds, 1);

      await previous(tester);
      expectPage('lesson-slicing', 'STRINGS', '1 / 2');
      await previous(tester);
      expectPage('lesson-install', 'SETUP', '1 / 1');
      await previous(tester);
      expectPage('lesson-four', 'BASICS', '4 / 4');

      await unmount(tester);
    });

    testWidgets('a page of an earlier goal that leaves the curriculum falls '
        'back to the newest page', (tester) async {
      await mountOnMethods(tester);
      await previous(tester);
      await previous(tester);
      expectPage('lesson-four', 'BASICS', '4 / 4');

      // The teacher unlinks the lesson the student is reading.
      goals.docs['s4']!['contentId'] = null;
      await tester.pump(kCosmosPollInterval);
      await settlePage(tester);

      expectPage('lesson-methods', 'STRINGS', '2 / 2');
      expect(find.text('Next'), findsNothing);
      expect(containerOf(tester).read(viewedContentIdProvider), 'd2');

      await unmount(tester);
    });
  });
}
