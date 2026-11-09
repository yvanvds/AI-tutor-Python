// #129, #301: the "Puntenformule" page opens on the short explanation for
// students in the app's language, and the bar at the bottom switches to the
// full formula (the specification, Dutch only) and back. Both go through
// `LessonHtmlView` — the same view the theory pages use, so the documents
// get the lesson stylesheet and one WebView host — and the switch keeps that
// one host: the fragment changes in place (#128).
//
// Mounted on the in-memory `FakeWebViewPlatform`; the assets are the real
// documents, read through the test asset bundle. The real Windows WebView
// rendering the real documents is `integration_test/flows/puntenformule_tab.dart`.

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

const _englishTitle = 'How do you get your grade?';
const _dutchTitle = 'Hoe kom je aan je punt?';

void main() {
  late FakeWebViewPlatform webviews;

  setUp(() {
    webviews = FakeWebViewPlatform.install();
  });

  Widget app({
    List<Override> overrides = const [],
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    overrides: [
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
      ...overrides,
    ],
    child: localizedTestApp(const Scaffold(body: _Host()), locale: locale),
  );

  Future<void> mount(
    WidgetTester tester, {
    List<Override> overrides = const [],
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(overrides: overrides, locale: locale));
  }

  /// Asset load + conversion, then the view's stylesheet load, channel
  /// registration and page load.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  LessonHtmlView view(WidgetTester tester) =>
      tester.widget<LessonHtmlView>(find.byType(LessonHtmlView));

  String headerNote(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('puntenformule-header-note')))
      .data!;

  testWidgets('shows the loading note until the short text is converted', (
    tester,
  ) async {
    await mount(tester);

    expect(find.text('Loading the grade formula…'), findsOneWidget);
    expect(find.byType(LessonHtmlView), findsNothing);

    await settle(tester);

    expect(find.text('Loading the grade formula…'), findsNothing);
    expect(find.byType(LessonHtmlView), findsOneWidget);
  });

  testWidgets('in English the tab opens on the English short text, and the '
      'way to the full formula says it is in Dutch', (tester) async {
    await mount(tester);
    await settle(tester);

    final shown = view(tester);
    expect(shown.language, 'en');
    expect(shown.fragment, contains(_englishTitle));
    expect(shown.fragment, isNot(contains(_dutchTitle)));
    // The short text: a formula block, no tables.
    expect(shown.fragment, contains('<pre><code>'));
    expect(shown.fragment, isNot(contains('<table>')));
    expect(shown.fragment, isNot(contains('class="run"')));

    // And the view wrapped it in the lesson document: the shared stylesheet
    // is inlined around the same fragment.
    final page = webviews.controllers.single.currentHtml;
    expect(page, contains('<body class="lesson">'));
    expect(page, contains('body.lesson {'));
    expect(page, contains(shown.fragment));

    expect(find.text('GRADE FORMULA'), findsOneWidget);
    expect(headerNote(tester), contains('in short'));
    expect(find.text('Read the full formula (in Dutch)'), findsOneWidget);
    expect(find.byKey(const Key('puntenformule-show-full')), findsOneWidget);
    expect(find.byKey(const Key('puntenformule-show-short')), findsNothing);
  });

  testWidgets('in Dutch the tab opens on the Dutch short text', (tester) async {
    await mount(tester, locale: const Locale('nl'));
    await settle(tester);

    final shown = view(tester);
    expect(shown.language, 'nl');
    expect(shown.fragment, contains(_dutchTitle));
    expect(shown.fragment, isNot(contains(_englishTitle)));

    expect(find.text('PUNTENFORMULE'), findsOneWidget);
    expect(headerNote(tester), contains('kort uitgelegd'));
    expect(find.text('Lees de volledige formule'), findsOneWidget);
  });

  testWidgets('the bar at the bottom switches to the full formula and back, '
      'in the one WebView (#128)', (tester) async {
    await mount(tester);
    await settle(tester);
    final shortFragment = view(tester).fragment;
    final controller = webviews.controllers.single;

    // The bar sits under the document.
    final toFull = find.byKey(const Key('puntenformule-show-full'));
    expect(
      tester.getTopLeft(toFull).dy,
      greaterThan(tester.getBottomLeft(find.byType(LessonHtmlView)).dy - 1),
    );

    await tester.tap(toFull);
    await settle(tester);

    final full = view(tester);
    expect(full.language, 'nl');
    expect(full.fragment, matches(RegExp(r'^<h1[^>]*>Puntenformule')));
    expect(full.fragment, contains('<table>'));
    expect(full.fragment, contains('<strong>Versie '));
    expect(controller.currentHtml, contains(full.fragment));
    expect(headerNote(tester), contains('full grade formula, in Dutch'));
    expect(find.text('Back to the short explanation'), findsOneWidget);
    expect(find.byKey(const Key('puntenformule-show-full')), findsNothing);

    await tester.tap(find.byKey(const Key('puntenformule-show-short')));
    await settle(tester);

    expect(view(tester).fragment, shortFragment);
    expect(view(tester).language, 'en');
    expect(controller.currentHtml, contains(shortFragment));
    expect(find.text('Read the full formula (in Dutch)'), findsOneWidget);

    // One WebView host the whole way: the fragment navigated in place, it
    // was never swapped for a loading note and mounted again.
    expect(webviews.controllers, hasLength(1));
    expect(webviews.widgetsCreated, 1);
    expect(find.text('Loading the grade formula…'), findsNothing);
  });

  testWidgets('a new visit opens on the short text again', (tester) async {
    await mount(tester);
    await settle(tester);
    await tester.tap(find.byKey(const Key('puntenformule-show-full')));
    await settle(tester);
    expect(view(tester).fragment, matches(RegExp(r'^<h1[^>]*>Puntenformule')));

    // Away (the shell swaps the section's page out) and back.
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    await settle(tester);

    expect(view(tester).fragment, contains(_englishTitle));
    expect(find.byKey(const Key('puntenformule-show-full')), findsOneWidget);
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
          (ref, assetKey) => Future<String>.error(StateError('asset missing')),
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
    // The way to the other document stays: one missing file does not lock
    // the tab.
    expect(find.byKey(const Key('puntenformule-show-full')), findsOneWidget);
  });
}
