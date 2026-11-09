// End-to-end (#129, #301): the grade formula ships with the app. Sam opens
// the "Grade formula" entry in the sidebar and reads the short explanation
// for students in the app's language — `docs/puntenformule-leerlingen.en.md`
// here, the `.nl.md` once the app is switched to Dutch — and the bar at the
// bottom of the tab takes Sam to the full formula, `docs/PUNTENFORMULE.md`,
// and back. Both are the documents bundled into this very build, converted
// from Markdown on the way in and rendered by the real Windows WebView
// through the lesson view.
//
// What only a full-app run can pin: the assets are really declared and
// really in the bundle (a widget test reads them from the test asset
// directory), the conversion happens in the running app, and WebView2 lays
// the result out — headings, formula blocks and tables are read *inside the
// rendered page*, not in the string the page was given. The counts are
// cross-checked against the bundled sources, so the flow never hard-codes
// today's documents. The switch to the full formula and back has to happen
// in the one WebView (#128: the fragment changes in place, the native
// surface stays), the page has to hold still through a Cosmos poll, and a
// second visit opens on the short text again.
//
// The teacher flow pins who gets the entry: it sits in the student group,
// so a teacher reads the same documents the students do.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/puntenformule_tab.dart -d windows

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
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

/// The rendered page, as WebView2 has it: reads the live DOM of the
/// `LessonHtmlView` currently on screen.
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

/// What a bundled document should look like once rendered: its title and
/// how many tables and formula blocks it has, read from the source.
class _Expected {
  _Expected(String source)
    : title = RegExp(
        r'^# (.+)$',
        multiLine: true,
      ).firstMatch(source)!.group(1)!.trim(),
      tables = RegExp(
        r'^\|\s*-{3,}',
        multiLine: true,
      ).allMatches(source).length,
      formulaBlocks =
          RegExp(r'^```', multiLine: true).allMatches(source).length ~/ 2;

  final String title;
  final int tables;
  final int formulaBlocks;
}

Future<_Expected> _expect(String assetKey) async =>
    _Expected(await rootBundle.loadString(assetKey));

/// Waits until [expected] is up inside the WebView — its title is the
/// page's `h1` — and returns the handle to keep asking.
Future<_RenderedPage> _rendered(WidgetTester tester, _Expected expected) async {
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
  while ((await page.text('h1')).trim() != expected.title) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        '"${expected.title}" never rendered inside the WebView '
        '(h1 is "${await page.text('h1')}")',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  return page;
}

/// The rendered page has exactly the structure of its source.
Future<void> _matches(_RenderedPage page, _Expected expected) async {
  expect(await page.count('table'), expected.tables);
  expect(await page.count('pre > code'), expected.formulaBlocks);
  // A plain `<pre>` is inert: nothing in the documents asked for a live
  // preview and nothing got one; and no link can take the view away.
  expect(await page.count('pre.run'), 0);
  expect(await page.count('.run-output'), 0);
  expect(await page.count('a[href]'), 0);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a student reads the short explanation in the app\'s language, '
      'switches to the full formula and back in the one WebView, and the '
      'page holds still through a poll', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);
    expect(find.text('Hi Sam,'), findsOneWidget);

    // What this build carries — the expectations are read from the bundle,
    // so the flow follows the documents instead of pinning today's text.
    final shortEn = await _expect(kPuntenformuleStudentEnAssetKey);
    final shortNl = await _expect(kPuntenformuleStudentNlAssetKey);
    final full = await _expect(kPuntenformuleAssetKey);
    expect(shortEn.formulaBlocks, greaterThan(0));
    expect(shortEn.tables, 0);
    expect(full.tables, greaterThan(0));

    await tester.tap(find.byTooltip('Grade formula'));
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    // Top-bar subline and the page's own pill.
    expect(find.text('Grade formula'), findsOneWidget);
    expect(find.text('GRADE FORMULA'), findsOneWidget);

    // The tab opens on the short explanation, in English.
    final page = await _rendered(tester, shortEn);
    await _matches(page, shortEn);
    expect(harness.lessonRunner.ran, isEmpty);

    // The way to the full formula sits under the document and says the
    // full text is Dutch.
    final toFull = find.byKey(const Key('puntenformule-show-full'));
    expect(toFull, findsOneWidget);
    expect(find.text('Read the full formula (in Dutch)'), findsOneWidget);
    expect(
      tester.getTopLeft(toFull).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(LessonHtmlView)).dy - 1,
      ),
    );

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

    // To the full formula: the same WebView navigates in place, and every
    // table and formula block of the specification renders.
    await tester.tap(toFull);
    await _rendered(tester, full);
    await _matches(page, full);
    expect(tester.element(find.byType(WebViewWidget)), same(webviewBefore));
    expect(tester.element(surface), same(surfaceBefore));
    expect(find.textContaining('full grade formula, in Dutch'), findsOneWidget);

    // And back.
    await tester.tap(find.byKey(const Key('puntenformule-show-short')));
    await _rendered(tester, shortEn);
    await _matches(page, shortEn);
    expect(tester.element(find.byType(WebViewWidget)), same(webviewBefore));
    expect(find.text('Read the full formula (in Dutch)'), findsOneWidget);

    // Away and back: a fresh view, the cached document, and the short
    // explanation again — even after leaving from the full formula.
    await tester.tap(toFull);
    await _rendered(tester, full);
    await tester.tap(find.byTooltip('Session'));
    await pumpUntilFound(tester, find.byType(SessionView));
    expect(find.byType(PuntenformulePage), findsNothing);

    await tester.tap(find.byTooltip('Grade formula'));
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    final again = await _rendered(tester, shortEn);
    expect(
      tester.element(find.byType(WebViewWidget)),
      isNot(same(webviewBefore)),
    );
    await _matches(again, shortEn);

    // In Dutch, the tab shows the Dutch explanation.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Puntenformule'));
    await pumpUntilFound(tester, find.byType(PuntenformulePage));
    expect(find.text('PUNTENFORMULE'), findsOneWidget);
    final dutch = await _rendered(tester, shortNl);
    await _matches(dutch, shortNl);
    expect(find.text('Lees de volledige formule'), findsOneWidget);
    await tester.tap(find.byKey(const Key('puntenformule-show-full')));
    await _rendered(tester, full);
    await _matches(dutch, full);

    // Back to English for whatever runs next in this process.
    await tester.tap(find.byTooltip('Opties'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('English'));
    await pumpUntilFound(tester, find.text('Options'));

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
    await _rendered(tester, await _expect(kPuntenformuleStudentEnAssetKey));
    await tester.tap(find.byKey(const Key('puntenformule-show-full')));
    await _rendered(tester, await _expect(kPuntenformuleAssetKey));

    await harness.dispose(tester);
  });
}
