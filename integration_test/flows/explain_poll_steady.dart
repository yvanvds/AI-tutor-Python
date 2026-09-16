// End-to-end (#128): the lesson page no longer blinks every 5 s. Sam opens
// the "Print" lesson and just reads it while the Cosmos polls tick under
// the view. Before the fix every sibling poll rebuilt `ExplainView`, which
// re-created its `WebViewWidget`, whose Windows build handed a
// `FutureBuilder` a new future: one frame of nothing where the page was,
// then a freshly mounted texture — a visible blink on a slow laptop.
//
// The surface under test is the *real* Windows WebView: the `Texture` the
// platform widget paints the page into. It has to be the same element
// before and after two polls, and present in every frame in between. As the
// positive control, the teacher then edits the lesson: the new page loads
// (its own `<pre class="run">` reaches the runner) in that same texture —
// a content change navigates in place, it does not re-mount either.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/explain_poll_steady.dart -d windows

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// The Python inside the edited lesson's live-preview block — distinct from
/// `kLessonExampleCode`, so the runner tells the new page from the old.
const String kEditedExampleCode = 'print("bewerkt")';

const String kEditedBody =
    '<h2>Print</h2>'
    '<p>Bewerkt door de leerkracht.</p>'
    '<pre class="run"><code>$kEditedExampleCode</code></pre>';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the lesson surface survives two polls untouched, and a '
      'content edit navigates it in place', (tester) async {
    final harness = AppHarness(
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
        kEditedExampleCode: const LessonRunResult(stdout: 'bewerkt'),
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    Future<void> lessonOnScreen(String code) => pumpUntil(
      tester,
      () =>
          harness.lessonRunner.ran.isNotEmpty &&
          harness.lessonRunner.ran.last == code,
      timeout: const Duration(seconds: 30),
      reason: 'the lesson page with "$code" never loaded',
    );

    // The page is up: its bootstrap ran the example through the bridge.
    await lessonOnScreen(kLessonExampleCode);
    expect(find.text('1 / 2'), findsOneWidget);

    // The native surface the page is painted into.
    final surface = find.descendant(
      of: find.byType(LessonHtmlView),
      matching: find.byType(Texture),
    );
    await pumpUntilFound(tester, surface);
    final webviewBefore = tester.element(find.byType(WebViewWidget));
    final surfaceBefore = tester.element(surface);
    final runsBefore = harness.lessonRunner.ran.length;

    // Sit through two sibling/content polls, looking at every frame.
    var blankFrames = 0;
    final deadline = DateTime.now().add(
      kCosmosPollInterval * 2 + const Duration(seconds: 1),
    );
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (surface.evaluate().isEmpty) blankFrames++;
    }

    expect(
      blankFrames,
      0,
      reason: 'the lesson surface was missing from $blankFrames frame(s)',
    );
    expect(
      tester.element(find.byType(WebViewWidget)),
      same(webviewBefore),
      reason: 'the WebViewWidget was re-mounted during the polls',
    );
    expect(
      tester.element(surface),
      same(surfaceBefore),
      reason: 'the WebView texture was re-mounted during the polls',
    );
    // Nothing reloaded either: the page ran its example exactly once.
    expect(harness.lessonRunner.ran, hasLength(runsBefore));
    expect(find.text('1 / 2'), findsOneWidget);

    // The teacher edits the lesson; the next content poll brings the new
    // page — into the same surface.
    harness.cosmos['content'].docs['s1']!['body'] = kEditedBody;
    await lessonOnScreen(kEditedExampleCode);

    expect(
      tester.element(find.byType(WebViewWidget)),
      same(webviewBefore),
      reason: 'a content change re-mounted the WebViewWidget',
    );
    expect(
      tester.element(surface),
      same(surfaceBefore),
      reason: 'a content change re-mounted the WebView texture',
    );
    expect(find.text('1 / 2'), findsOneWidget);

    await harness.dispose(tester);
  });
}
