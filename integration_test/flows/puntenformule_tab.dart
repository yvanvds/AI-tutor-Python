// End-to-end (#129): the grade formula ships with the app. Sam opens the
// "Grade formula" entry in the sidebar and reads `docs/PUNTENFORMULE.md` —
// the document bundled into this very build, converted from Markdown on the
// way in and rendered by the real Windows WebView through the lesson view.
//
// What only a full-app run can pin: the asset is really declared and really
// in the bundle (a widget test reads it from the test asset directory), the
// conversion happens in the running app, and WebView2 lays the result out —
// the tables and formula blocks are counted *inside the rendered page*, not
// in the string the page was given. The counts are cross-checked against
// the bundled source, so the flow never hard-codes today's document. The
// page then has to hold still through a Cosmos poll (#128: a second WebView
// host must not blink either), and a second visit — the converted document
// is cached by then — has to render just as well.
//
// The teacher flow pins who gets the entry: it sits in the student group,
// so a teacher reads the same document the students do.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/puntenformule_tab.dart -d windows

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/puntenformule/puntenformule_page.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart'
    show PlatformWebViewController;

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// The rendered page, as WebView2 has it: counts elements in the live DOM
/// of the `LessonHtmlView` currently on screen.
class _RenderedPage {
  _RenderedPage(WidgetTester tester)
    : _controller = tester
          .widget<WebViewWidget>(
            find.descendant(
              of: find.byType(LessonHtmlView),
              matching: find.byType(WebViewWidget),
            ),
          )
          .platform
          .params
          .controller;

  final PlatformWebViewController _controller;

  Future<int> count(String selector) async {
    final result = await _controller.runJavaScriptReturningResult(
      "document.querySelectorAll('$selector').length",
    );
    return (result as num).toInt();
  }

  Future<String> text(String selector) async {
    final result = await _controller.runJavaScriptReturningResult(
      "(document.querySelector('$selector') || {textContent: ''}).textContent",
    );
    return result as String;
  }
}

/// Waits until the document is up inside the WebView — its first table is
/// in the DOM — and returns the handle to keep asking.
Future<_RenderedPage> _documentRendered(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(LessonHtmlView));
  await pumpUntilFound(
    tester,
    find.descendant(
      of: find.byType(LessonHtmlView),
      matching: find.byType(Texture),
    ),
  );
  final page = _RenderedPage(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (await page.count('table') == 0) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the grade formula never rendered a table inside the WebView');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  return page;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a student opens the grade formula: the bundled document '
      'renders in the real WebView, holds still through a poll, and renders '
      'again on a second visit', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);
    expect(find.text('Hi Sam,'), findsOneWidget);

    // What this build carries — the expectation is read from the bundle, so
    // the flow follows the document instead of pinning today's numbers.
    final source = await rootBundle.loadString(kPuntenformuleAssetKey);
    final tablesInSource = RegExp(
      r'^\|\s*-{3,}',
      multiLine: true,
    ).allMatches(source).length;
    final fencesInSource = RegExp(
      r'^```',
      multiLine: true,
    ).allMatches(source).length;
    expect(tablesInSource, greaterThan(0));
    expect(fencesInSource.isEven, isTrue);

    await tester.tap(find.byTooltip('Grade formula'));
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    // Top-bar subline and the page's own pill.
    expect(find.text('Grade formula'), findsOneWidget);
    expect(find.text('GRADE FORMULA'), findsOneWidget);

    final page = await _documentRendered(tester);
    expect(await page.text('h1'), startsWith('Puntenformule'));
    expect(await page.count('table'), tablesInSource);
    expect(await page.count('pre > code'), fencesInSource ~/ 2);
    // A plain `<pre>` is inert: nothing in the document asked for a live
    // preview and nothing got one.
    expect(await page.count('pre.run'), 0);
    expect(await page.count('.run-output'), 0);
    expect(harness.lessonRunner.ran, isEmpty);

    // Hold still through a Cosmos poll (#128): the same WebView, the same
    // texture, in every frame.
    final surface = find.descendant(
      of: find.byType(LessonHtmlView),
      matching: find.byType(Texture),
    );
    final webviewBefore = tester.element(find.byType(WebViewWidget));
    final surfaceBefore = tester.element(surface);
    var blankFrames = 0;
    final deadline = DateTime.now().add(
      kCosmosPollInterval + const Duration(seconds: 1),
    );
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (surface.evaluate().isEmpty) blankFrames++;
    }
    expect(
      blankFrames,
      0,
      reason: 'the document surface was missing from $blankFrames frame(s)',
    );
    expect(tester.element(find.byType(WebViewWidget)), same(webviewBefore));
    expect(tester.element(surface), same(surfaceBefore));
    expect(await page.count('table'), tablesInSource);

    // Away and back: a fresh view, the cached document, the same page.
    await tester.tap(find.byTooltip('Session'));
    await pumpUntilFound(tester, find.byType(SessionView));
    expect(find.byType(PuntenformulePage), findsNothing);

    await tester.tap(find.byTooltip('Grade formula'));
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    final again = await _documentRendered(tester);
    expect(
      tester.element(find.byType(WebViewWidget)),
      isNot(same(webviewBefore)),
    );
    expect(await again.count('table'), tablesInSource);
    expect(await again.text('h1'), startsWith('Puntenformule'));

    await harness.dispose(tester);
  });

  testWidgets('a teacher has the same entry, in the student group', (
    tester,
  ) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    expect(find.text('Hi Yvan,'), findsOneWidget);

    final entry = find.byTooltip('Grade formula');
    expect(entry, findsOneWidget);
    expect(
      tester.getTopLeft(entry).dy,
      lessThan(tester.getTopLeft(find.text('TEACHER')).dy),
    );

    await tester.tap(entry);
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    final page = await _documentRendered(tester);
    expect(await page.text('h1'), startsWith('Puntenformule'));

    await harness.dispose(tester);
  });
}
