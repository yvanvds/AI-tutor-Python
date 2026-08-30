// Issue #13 — lesson content can pair a code block with a live preview of
// its output: `<pre class="run">` blocks are executed for real when the
// lesson opens and the captured output is shown under the code.
//
// This mounts the real `ExplainView` (header pill, WebView host, footer)
// over the real `ContentService` / `GoalsService` on an in-memory Cosmos,
// with the WebView platform replaced by an in-memory fake that records the
// document loaded and the scripts pushed into it. The page's side of the
// bridge is played by posting on the JavaScript channel exactly as the
// injected bootstrap does; Python itself is a scripted `LessonCodeRunner`
// (the bundled host only exists next to an installed exe).
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'dart:convert';

import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/widgets/lesson_document.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_lesson_code_runner.dart';
import '../../helpers/fake_webview_platform.dart';
import '../../helpers/in_memory_cosmos.dart';

const _helloCode = 'naam = "Mira"\nprint("Hallo", naam)';
const _brokenCode = 'print(1 / 0)';
const _traceback =
    'Traceback (most recent call last):\n'
    '  File "<student>", line 1, in <module>\n'
    'ZeroDivisionError: division by zero';

const _lessonBody =
    '<h2>Print</h2>'
    '<p>Zo toon je iets op het scherm.</p>'
    '<pre class="run"><code>$_helloCode</code></pre>'
    '<pre><code>print("geen preview")</code></pre>'
    '<pre class="run"><code>$_brokenCode</code></pre>';

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

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

/// What the page posts for block [index] holding [code].
String _runMessage(int index, String code) =>
    jsonEncode({'id': 'run-$index', 'code': code});

void main() {
  late FakeWebViewPlatform webviews;
  late FakeLessonCodeRunner runner;
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late InMemoryCosmos modules;

  final root = Goal(id: 'r1', title: 'Basics', order: 1000);
  final child = Goal(
    id: 's1',
    title: 'Print',
    parentId: 'r1',
    order: 1000,
    contentId: 's1',
  );

  setUp(() {
    webviews = FakeWebViewPlatform.install();
    runner = FakeLessonCodeRunner(
      results: {
        _helloCode: const LessonRunResult(stdout: 'Hallo Mira'),
        _brokenCode: const LessonRunResult(stderr: _traceback),
      },
    );
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Basics'),
      _goal(id: 's1', title: 'Print', parentId: 'r1', contentId: 's1'),
    ]);
    content = InMemoryCosmos([
      {'id': 's1', 'type': 'content', 'title': 'Print', 'body': _lessonBody},
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

  List<Override> overrides() => [
    goalSelectionProvider.overrideWith(() => _PresetSelection(root, child)),
    goalsServiceProvider.overrideWithValue(
      GoalsService(container: goals.container),
    ),
    contentServiceProvider.overrideWith(
      () => ContentService(container: content.container),
    ),
    moduleServiceProvider.overrideWith(
      () => ModuleService(container: modules.container),
    ),
    lessonCodeRunnerProvider.overrideWithValue(runner),
  ];

  Widget app(Widget home) => ProviderScope(
    overrides: overrides(),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    ),
  );

  Future<void> mount(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(home));
    // Content poll, stylesheet asset load, channel registration, page load.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  FakeWebViewController page() {
    expect(webviews.controllers, hasLength(1));
    return webviews.controllers.single;
  }

  group('student explain view', () {
    testWidgets('the lesson loads with the live-preview bootstrap around the '
        'authored blocks', (tester) async {
      await mount(tester, const ExplainView());

      expect(find.byType(LessonHtmlView), findsOneWidget);
      final html = page().currentHtml;
      expect(html, contains(_lessonBody));
      expect(html, contains("querySelectorAll('pre.run')"));
      expect(html, contains('"output":"Output"'));
      expect(html, contains('"run":"Run"'));
      expect(page().channels.keys, contains(kLessonRunnerChannel));
      // Nothing runs until the page asks.
      expect(runner.ran, isEmpty);

      await unmount(tester);
    });

    testWidgets('a run request from the page is executed and its output '
        'delivered back under that block', (tester) async {
      await mount(tester, const ExplainView());

      page().postMessage(kLessonRunnerChannel, _runMessage(0, _helloCode));
      await tester.pump();
      await tester.pump();

      expect(runner.ran, [_helloCode]);
      expect(page().executedJs, [
        lessonRunDeliverJs(
          'run-0',
          const LessonRunResult(stdout: 'Hallo Mira'),
        ),
      ]);
      expect(page().executedJs.single, contains('"stdout":"Hallo Mira"'));

      await unmount(tester);
    });

    testWidgets('a failing example delivers its traceback as stderr', (
      tester,
    ) async {
      await mount(tester, const ExplainView());

      page().postMessage(kLessonRunnerChannel, _runMessage(1, _brokenCode));
      await tester.pump();
      await tester.pump();

      expect(runner.ran, [_brokenCode]);
      final js = page().executedJs.single;
      expect(js, startsWith('window.__lessonRunDeliver("run-1"'));
      expect(js, contains('ZeroDivisionError: division by zero'));
      expect(js, contains('"stdout":""'));

      await unmount(tester);
    });

    testWidgets('every block on the page gets its own run, in order', (
      tester,
    ) async {
      await mount(tester, const ExplainView());

      page().postMessage(kLessonRunnerChannel, _runMessage(0, _helloCode));
      page().postMessage(kLessonRunnerChannel, _runMessage(1, _brokenCode));
      await tester.pump();
      await tester.pump();

      expect(runner.ran, [_helloCode, _brokenCode]);
      expect(page().executedJs, hasLength(2));
      expect(page().executedJs[0], contains('"run-0"'));
      expect(page().executedJs[1], contains('"run-1"'));

      await unmount(tester);
    });

    testWidgets('a malformed message from the page is ignored', (tester) async {
      await mount(tester, const ExplainView());

      page().postMessage(kLessonRunnerChannel, 'not json');
      page().postMessage(kLessonRunnerChannel, '{"id":"run-0"}');
      await tester.pump();

      expect(runner.ran, isEmpty);
      expect(page().executedJs, isEmpty);

      await unmount(tester);
    });

    testWidgets('a run that finishes after the lesson was replaced is not '
        'delivered into the new page', (tester) async {
      runner = FakeLessonCodeRunner(manual: true);
      await mount(tester, const ExplainView());

      page().postMessage(kLessonRunnerChannel, _runMessage(0, _helloCode));
      await tester.pump();
      expect(runner.ran, [_helloCode]);

      // Teacher edits the lesson; the next poll reloads the page.
      content.docs['s1']!['body'] = '<p>nieuw</p>';
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      await tester.pump();
      expect(page().loadedHtml, hasLength(2));
      expect(page().currentHtml, contains('<p>nieuw</p>'));

      runner.complete(const LessonRunResult(stdout: 'late'));
      await tester.pump();
      await tester.pump();
      expect(page().executedJs, isEmpty);

      await unmount(tester);
    });
  });

  group('teacher preview', () {
    testWidgets('the Lesinhoud preview runs the same live-preview blocks', (
      tester,
    ) async {
      await mount(tester, const LessonContentPage());
      await tester.pump();

      // The subgoal row shows the goal title and the lesson title (both
      // "Print"); either hit selects the row.
      await tester.tap(find.text('Print').first);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(find.byType(LessonHtmlView), findsOneWidget);
      expect(page().currentHtml, contains(_lessonBody));
      expect(page().currentHtml, contains("querySelectorAll('pre.run')"));

      page().postMessage(kLessonRunnerChannel, _runMessage(0, _helloCode));
      await tester.pump();
      await tester.pump();

      expect(runner.ran, [_helloCode]);
      expect(page().executedJs.single, contains('"stdout":"Hallo Mira"'));

      await unmount(tester);
    });
  });
}
