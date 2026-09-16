// End-to-end (#131): in the theory view the chat panel takes 460 px of a
// student laptop for a tutor who does not talk about the theory. Sam opens
// the "Print" lesson, folds the chat from its header, and the lesson takes
// the room; the fold is remembered on this device. A tutor message that
// lands behind the folded strip shows as a dot on it. "Try it yourself"
// always brings the full panel back (the tutor's questions live there),
// the Explain pill folds it again, and "Show chat" on the strip ends the
// fold.
//
// The surface under the fold is the *real* Windows WebView: the `Texture`
// the platform widget paints the lesson into. Sliding the chat re-lays the
// lesson out at a new width, and that must not re-mount the WebView or blank
// a frame — the same guarantee #128 makes for the 5 s polls, now for a
// layout change the student triggers.
//
// Since #138 the student on a small laptop does not have to find the button
// first: with no choice stored, a window under 1200 px starts the lesson
// with the chat folded, the panel follows the window across that line until
// either button is pressed, and a stored "open" is open on a small screen.
// The window is sized through the test view (see `AppHarness.windowSize`),
// and resized mid-flow the way a student drags the window edge.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/chat_collapse.dart -d windows

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_all/webview_all.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// Either side of the 1200 px fold line (#138), in logical pixels.
const double _wideWindow = 1400;
const double _narrowWindow = 1000;

/// Fresh finders per call: a reused instance caches elements that a mode
/// swap has since unmounted (#133).
Finder _panel() => find.byKey(const Key('chat-panel'));
Finder _showChat() => find.byTooltip('Show chat');
Finder _hideChat() => find.byTooltip('Hide chat');
Finder _unreadDot() => find.byKey(const Key('chat-unread-dot'));
Finder _surface() => find.descendant(
  of: find.byType(LessonHtmlView),
  matching: find.byType(Texture),
);

double _panelWidth(WidgetTester tester) => tester.getSize(_panel()).width;
double _lessonWidth(WidgetTester tester) =>
    tester.getSize(find.byType(ExplainView)).width;

/// Resizes the app window to [width] logical pixels, keeping the harness's
/// height and the machine's pixel ratio.
void _resize(WidgetTester tester, double width) {
  tester.view.physicalSize =
      Size(width, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
}

/// Pumps until the chat panel has slid to [width], watching every frame for
/// the lesson surface, and returns how many frames it was missing from.
Future<int> _slideTo(WidgetTester tester, double width) async {
  var blankFrames = 0;
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (_panelWidth(tester) != width) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the chat panel never reached $width px');
    }
    await tester.pump(const Duration(milliseconds: 50));
    if (_surface().evaluate().isEmpty) blankFrames++;
  }
  await tester.pump();
  return blankFrames;
}

Future<void> _openLesson(WidgetTester tester, AppHarness harness) async {
  await tester.tap(find.byTooltip('Learning path'));
  await pumpUntilFound(tester, find.byType(LeerpadPage));
  await tester.tap(find.text('Continue'));
  await pumpUntilFound(tester, find.byType(ExplainView));
  // The page is up: its bootstrap ran the example through the bridge.
  await pumpUntil(
    tester,
    () =>
        harness.lessonRunner.ran.isNotEmpty &&
        harness.lessonRunner.ran.last == kLessonExampleCode,
    timeout: const Duration(seconds: 30),
    reason: 'the lesson page never loaded',
  );
  await pumpUntilFound(tester, _surface());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Hide chat folds the panel to a strip without touching the '
      'lesson surface; the fold is remembered, a message behind it shows a '
      'dot, practice always has the full panel, Show chat ends the fold', (
    tester,
  ) async {
    final harness = AppHarness(
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);
    await _openLesson(tester, harness);

    // Default: the full panel, no strip.
    expect(_panelWidth(tester), chatPanelWidth);
    expect(_showChat(), findsNothing);
    expect(_hideChat(), findsOneWidget);
    final lessonBefore = _lessonWidth(tester);
    final webviewBefore = tester.element(find.byType(WebViewWidget));
    final surfaceBefore = tester.element(_surface());
    final runsBefore = harness.lessonRunner.ran.length;

    // Fold.
    await tester.tap(_hideChat());
    final blankOnFold = await _slideTo(tester, chatCollapsedWidth);

    expect(_showChat(), findsOneWidget);
    expect(
      _lessonWidth(tester) - lessonBefore,
      chatPanelWidth - chatCollapsedWidth,
      reason: 'the lesson takes exactly the room the chat gave up',
    );
    expect(
      blankOnFold,
      0,
      reason: 'the lesson surface was missing from $blankOnFold frame(s)',
    );
    expect(
      tester.element(find.byType(WebViewWidget)),
      same(webviewBefore),
      reason: 'folding the chat re-mounted the WebViewWidget',
    );
    expect(
      tester.element(_surface()),
      same(surfaceBefore),
      reason: 'folding the chat re-mounted the WebView texture',
    );
    expect(
      harness.lessonRunner.ran,
      hasLength(runsBefore),
      reason: 'the lesson must not reload on a fold',
    );

    // Remembered on this device.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kChatCollapsedPrefsKey), isTrue);

    // A tutor message behind the strip: the dot.
    expect(_unreadDot(), findsNothing);
    harness.container
        .read(chatServiceProvider)
        .addTutorMessage('Have a look at the second paragraph.');
    await pumpUntilFound(tester, _unreadDot());

    // Practice always has the full panel, whatever the fold says — and the
    // message is on screen, so the dot is done.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => _panelWidth(tester) == chatPanelWidth,
      reason: 'the chat never slid back to full width in practice',
    );
    await pumpUntilGone(tester, find.byType(ExplainView));
    expect(harness.container.read(modeProvider), SessionMode.practice);
    expect(harness.container.read(chatCollapsedProvider), isTrue);
    expect(_showChat(), findsNothing);
    expect(_unreadDot(), findsNothing);
    // The bubble renders through `TutorMarkdown` (a `RichText`), so a plain
    // `find.text` never sees it.
    expect(
      find.textContaining('second paragraph', findRichText: true),
      findsOneWidget,
      reason: 'the message that was behind the strip is in the chat',
    );

    // Back to the theory: folded again, as remembered.
    await tester.tap(find.text('Explain'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntilGone(tester, find.byType(PracticeView));
    await _slideTo(tester, chatCollapsedWidth);
    expect(_showChat(), findsOneWidget);
    expect(_unreadDot(), findsNothing);

    // Show chat ends the fold — without touching the lesson surface either —
    // and that is remembered too.
    await pumpUntilFound(tester, _surface());
    final surfaceAfterReturn = tester.element(_surface());
    await tester.tap(_showChat());
    final blankOnUnfold = await _slideTo(tester, chatPanelWidth);
    expect(
      blankOnUnfold,
      0,
      reason: 'the lesson surface was missing from $blankOnUnfold frame(s)',
    );
    expect(tester.element(_surface()), same(surfaceAfterReturn));
    expect(_showChat(), findsNothing);
    expect(_hideChat(), findsOneWidget);
    expect(prefs.getBool(kChatCollapsedPrefsKey), isFalse);

    await harness.dispose(tester);
  });

  testWidgets('with no choice stored, a narrow window starts the lesson with '
      'the chat folded; the panel follows the window until Show chat makes '
      'open the decision, which then holds on any window', (tester) async {
    final harness = AppHarness(
      windowSize: const Size(_narrowWindow, 720),
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);
    await _openLesson(tester, harness);

    // Folded from the first frame of the lesson, and nothing was decided
    // for the student: no choice in the notifier, nothing in the store.
    expect(_panelWidth(tester), chatCollapsedWidth);
    expect(_showChat(), findsOneWidget);
    expect(_unreadDot(), findsNothing);
    expect(harness.container.read(chatCollapsedProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kChatCollapsedPrefsKey), isFalse);
    final lessonFolded = _lessonWidth(tester);
    final webviewBefore = tester.element(find.byType(WebViewWidget));
    final surfaceBefore = tester.element(_surface());
    final runsBefore = harness.lessonRunner.ran.length;

    // Wider than the line: still no choice, so the panel unfolds — without
    // touching the lesson surface.
    _resize(tester, _wideWindow);
    final blankOnUnfold = await _slideTo(tester, chatPanelWidth);
    expect(
      blankOnUnfold,
      0,
      reason: 'the lesson surface was missing from $blankOnUnfold frame(s)',
    );
    expect(_showChat(), findsNothing);
    expect(harness.container.read(chatCollapsedProvider), isNull);
    expect(
      _lessonWidth(tester),
      lessonFolded +
          (_wideWindow - _narrowWindow) -
          (chatPanelWidth - chatCollapsedWidth),
      reason: 'the lesson grew with the window, less what the chat took back',
    );
    expect(
      tester.element(find.byType(WebViewWidget)),
      same(webviewBefore),
      reason: 'the window fold re-mounted the WebViewWidget',
    );
    expect(tester.element(_surface()), same(surfaceBefore));
    expect(harness.lessonRunner.ran, hasLength(runsBefore));

    // Back under the line: folds again.
    _resize(tester, _narrowWindow);
    final blankOnFold = await _slideTo(tester, chatCollapsedWidth);
    expect(blankOnFold, 0);
    expect(_showChat(), findsOneWidget);
    expect(tester.element(_surface()), same(surfaceBefore));

    // Show chat on the narrow window: open is the decision now.
    await tester.tap(_showChat());
    await _slideTo(tester, chatPanelWidth);
    expect(harness.container.read(chatCollapsedProvider), isFalse);
    expect(prefs.getBool(kChatCollapsedPrefsKey), isFalse);

    // And the window no longer has a say: across the line and back, the
    // panel never leaves full width.
    _resize(tester, _wideWindow);
    await tester.pump(const Duration(milliseconds: 100));
    _resize(tester, _narrowWindow);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_panelWidth(tester), chatPanelWidth);
    }
    expect(_showChat(), findsNothing);
    expect(_hideChat(), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets('a stored "open" is in place on a narrow window from the first '
      'frame of the lesson: open, even on a small screen', (tester) async {
    final harness = AppHarness(
      windowSize: const Size(_narrowWindow, 720),
      prefs: {kChatCollapsedPrefsKey: false},
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);
    await _openLesson(tester, harness);

    expect(_panelWidth(tester), chatPanelWidth);
    expect(_showChat(), findsNothing);
    expect(_hideChat(), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets('a fold left by a previous launch is in place from the first '
      'frame of the lesson', (tester) async {
    final harness = AppHarness(
      prefs: {kChatCollapsedPrefsKey: true},
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);
    await _openLesson(tester, harness);

    expect(_panelWidth(tester), chatCollapsedWidth);
    expect(_showChat(), findsOneWidget);
    expect(_unreadDot(), findsNothing);

    await harness.dispose(tester);
  });
}
