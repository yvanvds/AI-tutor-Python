// #128: the lesson WebView used to blink on every 5 s poll. `LessonHtmlView`
// constructed a fresh `WebViewWidget` in every `build`, so any rebuild
// coming down from a host re-ran the platform widget's `build` — and on
// Windows that hands a `FutureBuilder` a new future, which draws one blank
// frame and re-mounts the native texture. The view now builds its
// `WebViewWidget` once and returns the same instance from every `build`, so
// a host may rebuild as often as it likes: the platform widget is created
// once and built once, for the life of the view.
//
// Mounted on the in-memory `FakeWebViewPlatform`, which counts platform
// widget creations and builds. The real Windows WebView surviving the real
// polls is `integration_test/flows/explain_poll_steady.dart`.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import '../helpers/fake_lesson_code_runner.dart';
import '../helpers/fake_webview_platform.dart';

/// A host that can be made to rebuild at will — the shape of every real
/// host: a parent whose own state changes while the fragment does not.
class _Host extends StatefulWidget {
  const _Host({required this.fragment});
  final String fragment;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int rebuilds = 0;
  String? _fragment;

  void rebuild({String? fragment}) => setState(() {
    rebuilds++;
    if (fragment != null) _fragment = fragment;
  });

  @override
  Widget build(BuildContext context) =>
      LessonHtmlView(fragment: _fragment ?? widget.fragment);
}

void main() {
  late FakeWebViewPlatform webviews;

  setUp(() {
    webviews = FakeWebViewPlatform.install();
  });

  Widget app() => ProviderScope(
    overrides: [
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: _Host(fragment: '<p>one</p>')),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(app());
    // Stylesheet asset load, channel registration, page load.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  _HostState host(WidgetTester tester) =>
      tester.state<_HostState>(find.byType(_Host));

  FakeWebViewController page() => webviews.controllers.single;

  testWidgets('a host rebuilding with the same fragment never reaches the '
      'platform widget', (tester) async {
    await mount(tester);
    expect(page().loadedHtml, hasLength(1));
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
    final before = tester.widget<WebViewWidget>(find.byType(WebViewWidget));

    host(tester).rebuild();
    await tester.pump();
    host(tester).rebuild();
    await tester.pump();

    expect(host(tester).rebuilds, 2);
    expect(
      tester.widget<WebViewWidget>(find.byType(WebViewWidget)),
      same(before),
      reason: 'the view handed the tree a new WebViewWidget',
    );
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
    // And nothing was reloaded: the page is the one loaded at mount.
    expect(page().loadedHtml, hasLength(1));
  });

  testWidgets('a changed fragment navigates the same WebView instead of '
      'mounting a new one', (tester) async {
    await mount(tester);
    final before = tester.widget<WebViewWidget>(find.byType(WebViewWidget));

    host(tester).rebuild(fragment: '<p>two</p>');
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(page().loadedHtml, hasLength(2));
    expect(page().currentHtml, contains('<p>two</p>'));
    expect(webviews.controllers, hasLength(1));
    expect(
      tester.widget<WebViewWidget>(find.byType(WebViewWidget)),
      same(before),
    );
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
  });

  testWidgets('the view reporting its page ready does not rebuild the '
      'platform widget either', (tester) async {
    // `_ready` flips via the view's own `setState` once the page is loaded:
    // that rebuild is internal to the view and must be as harmless as one
    // from a host.
    await tester.pumpWidget(app());
    await tester.pump();
    expect(webviews.widgetBuilds, 1);

    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(page().loadedHtml, hasLength(1));
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
  });
}
