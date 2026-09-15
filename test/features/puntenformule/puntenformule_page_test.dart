// #129: the "Puntenformule" page loads the bundled document, converts it
// and hands `LessonHtmlView` the fragment — the same view the theory pages
// use, so the document gets the lesson stylesheet and one WebView host.
//
// Mounted on the in-memory `FakeWebViewPlatform`; the asset is the real
// `docs/PUNTENFORMULE.md`, read through the test asset bundle. The real
// Windows WebView rendering the real document is
// `integration_test/flows/puntenformule_tab.dart`.

import 'package:ai_tutor_python/features/puntenformule/puntenformule_page.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_lesson_code_runner.dart';
import '../../helpers/fake_webview_platform.dart';
import '../../helpers/localization.dart';

/// A host that can be made to rebuild at will — the shape of the app shell,
/// whose own state changes (the 5 s account poll) while the page does not.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => const PuntenformulePage();
}

void main() {
  late FakeWebViewPlatform webviews;

  setUp(() {
    webviews = FakeWebViewPlatform.install();
  });

  Widget app({List<Override> overrides = const []}) => ProviderScope(
    overrides: [
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
      ...overrides,
    ],
    child: localizedTestApp(const Scaffold(body: _Host())),
  );

  Future<void> mount(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(overrides: overrides));
  }

  /// Asset load + conversion, then the view's stylesheet load, channel
  /// registration and page load.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('shows the loading note until the document is converted', (
    tester,
  ) async {
    await mount(tester);

    expect(find.text('Loading the grade formula…'), findsOneWidget);
    expect(find.byType(LessonHtmlView), findsNothing);

    await settle(tester);

    expect(find.text('Loading the grade formula…'), findsNothing);
    expect(find.byType(LessonHtmlView), findsOneWidget);
  });

  testWidgets('hands LessonHtmlView the converted document: tables, formula '
      'blocks and headings, and no live-preview block', (tester) async {
    await mount(tester);
    await settle(tester);

    final view = tester.widget<LessonHtmlView>(find.byType(LessonHtmlView));
    expect(view.fragment, contains('<h1'));
    expect(view.fragment, contains('<h2'));
    expect(view.fragment, contains('<table>'));
    expect(view.fragment, contains('<pre><code>'));
    expect(view.fragment, isNot(contains('class="run"')));

    // And the view wrapped it in the lesson document: the shared stylesheet
    // is inlined around the same fragment.
    final page = webviews.controllers.single.currentHtml;
    expect(page, contains('<body class="lesson">'));
    expect(page, contains('body.lesson {'));
    expect(page, contains(view.fragment));
  });

  testWidgets('header names the section and says what the document is', (
    tester,
  ) async {
    await mount(tester);
    await settle(tester);

    expect(find.text('GRADE FORMULA'), findsOneWidget);
    expect(find.textContaining('How your report grade is computed'), findsOne);
  });

  testWidgets('a host rebuild leaves the one WebView in place (#128)', (
    tester,
  ) async {
    await mount(tester);
    await settle(tester);
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);

    for (var i = 0; i < 3; i++) {
      tester.state<_HostState>(find.byType(_Host)).rebuild();
      await tester.pump();
    }

    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
    expect(webviews.controllers, hasLength(1));
  });

  testWidgets('a failed load shows the error instead of an empty view', (
    tester,
  ) async {
    await mount(
      tester,
      overrides: [
        puntenformuleFragmentProvider.overrideWith(
          (ref) => Future<String>.error(StateError('asset missing')),
        ),
      ],
    );
    await settle(tester);

    expect(find.byType(LessonHtmlView), findsNothing);
    expect(
      find.text(
        'The grade formula could not be loaded: Bad state: asset missing',
      ),
      findsOneWidget,
    );
  });
}
