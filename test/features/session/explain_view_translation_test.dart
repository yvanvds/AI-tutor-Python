// Issue #207 — the theory page shows the lesson in the language the student
// picked in Options. With a translation into that language the page is the
// translation; without one it is the Dutch lesson under a short notice that
// says so; in Dutch, the source language, it is the lesson as written, with
// no notice and nothing fetched from `translations`. The page follows the
// Dutch lesson, its translation and the language, and the document says
// which language it is in (`lang`). The header above the page names the
// root goal in the app language too (#210).
//
// Mounts the real `ExplainView` over the real `GoalsService`,
// `ContentService` and `TranslationService` on in-memory Cosmos containers,
// with the WebView platform replaced by the in-memory fake. The end-to-end
// version lives in `integration_test/flows/lesson_language.dart`.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_lesson_code_runner.dart';
import '../../helpers/fake_webview_platform.dart';
import '../../helpers/in_memory_cosmos.dart';

const _dutchBody = '<h2>Print</h2><p>Zo toon je iets op het scherm.</p>';
const _englishBody = '<h2>Print</h2><p>This is how you show something.</p>';
const _notice =
    'This lesson is not available in English yet, so it is shown in Dutch.';

final _lesson = Content(id: 's1', title: 'Print', body: _dutchBody);

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? parentId,
  String? contentId,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': 1000,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': contentId,
  'moduleId': 'python-basics',
};

Map<String, dynamic> _english(String body, {String title = 'Print'}) =>
    Translation.content(
      language: 'en',
      contentId: 's1',
      title: title,
      body: body,
      sourceHash: contentSourceHash(_lesson),
    ).toMap();

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

/// The real service, recording every language it was asked to fetch.
class _RecordingTranslations extends TranslationService {
  _RecordingTranslations(InMemoryCosmos store)
    : super(container: store.container);

  final List<String> watched = [];
  final List<String> fetched = [];

  @override
  Stream<List<Translation>> watchLanguage(String language) {
    watched.add(language);
    return super.watchLanguage(language);
  }

  @override
  Future<List<Translation>> listLanguage(String language) {
    fetched.add(language);
    return super.listLanguage(language);
  }
}

/// A content cache that never fills, so the view fetches the lesson on its
/// own (`watchById`) — the moment before the first poll comes back.
class _UncachedContent extends ContentService {
  _UncachedContent(InMemoryCosmos store) : super(container: store.container);

  @override
  List<Content> build() => const [];
}

/// Stands in for the language switch on the Options page.
final _locale = StateProvider<Locale>((_) => const Locale('en'));

void main() {
  late FakeWebViewPlatform webviews;
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late InMemoryCosmos translations;
  late _RecordingTranslations service;

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
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Basics'),
      _goal(id: 's1', title: 'Print', parentId: 'r1', contentId: 's1'),
    ]);
    content = InMemoryCosmos([_lesson.toMap()]);
    translations = InMemoryCosmos.partitioned('language', [
      _english(_englishBody),
    ]);
    service = _RecordingTranslations(translations);
  });

  Widget app(Locale locale, {bool cached = true}) => ProviderScope(
    overrides: [
      _locale.overrideWith((_) => locale),
      appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
      translationServiceProvider.overrideWithValue(service),
      goalSelectionProvider.overrideWith(() => _PresetSelection(root, child)),
      goalsServiceProvider.overrideWithValue(
        GoalsService(container: goals.container),
      ),
      contentServiceProvider.overrideWith(
        cached
            ? () => ContentService(container: content.container)
            : () => _UncachedContent(content),
      ),
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
    ],
    // The interface language follows the app locale, as in `main.dart`.
    child: Consumer(
      builder: (context, ref, _) => MaterialApp(
        locale: ref.watch(appLocaleProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ExplainView()),
      ),
    ),
  );

  /// Content poll, translations fetch, sibling poll, stylesheet asset load,
  /// channel registration, page load.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  Future<void> mount(
    WidgetTester tester,
    Locale locale, {
    bool cached = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(locale, cached: cached));
    await settle(tester);
  }

  /// One poll interval: every service fetches again.
  Future<void> poll(WidgetTester tester) async {
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
  }

  Future<void> switchTo(WidgetTester tester, Locale locale) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExplainView)),
    );
    container.read(_locale.notifier).state = locale;
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  FakeWebViewController page() => webviews.controllers.single;
  String shown() => page().currentHtml;

  testWidgets('English with a translation shows the translation, marked as '
      'English, without a notice', (tester) async {
    await mount(tester, const Locale('en'));

    expect(shown(), contains(_englishBody));
    expect(shown(), isNot(contains(_dutchBody)));
    expect(shown(), contains('<html lang="en">'));
    expect(find.text(_notice), findsNothing);

    await unmount(tester);
  });

  testWidgets('English without a translation shows the Dutch lesson, marked '
      'as Dutch, under a notice', (tester) async {
    translations.delete(Translation.contentDocId('s1'), partitionKey: 'en');
    await mount(tester, const Locale('en'));

    expect(shown(), contains(_dutchBody));
    expect(shown(), contains('<html lang="nl">'));
    expect(find.text(_notice), findsOneWidget);
    // Above the page, not over it.
    expect(
      tester.getBottomLeft(find.text(_notice)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(LessonHtmlView)).dy),
    );

    await unmount(tester);
  });

  testWidgets('Dutch shows the lesson as written, without a notice, and '
      'fetches nothing from translations', (tester) async {
    await mount(tester, const Locale('nl'));

    expect(shown(), contains(_dutchBody));
    expect(shown(), isNot(contains(_englishBody)));
    expect(shown(), contains('<html lang="nl">'));
    expect(find.textContaining('vertaald'), findsNothing);
    expect(find.byKey(const Key('explain-translation-missing')), findsNothing);
    expect(service.watched, isEmpty);
    expect(service.fetched, isEmpty);

    // Nor on a later poll.
    await poll(tester);
    expect(service.fetched, isEmpty);

    await unmount(tester);
  });

  testWidgets('switching the language shows the page in the new language at '
      'once, in the same WebView', (tester) async {
    await mount(tester, const Locale('nl'));
    expect(shown(), contains(_dutchBody));

    await switchTo(tester, const Locale('en'));
    expect(shown(), contains(_englishBody));
    expect(shown(), contains('<html lang="en">'));
    expect(find.text(_notice), findsNothing);

    await switchTo(tester, const Locale('nl'));
    expect(shown(), contains(_dutchBody));
    expect(shown(), contains('<html lang="nl">'));

    expect(webviews.widgetsCreated, 1);
    await unmount(tester);
  });

  testWidgets('the page follows its translation: a changed one reloads it, '
      'a removed one brings back the Dutch lesson with the notice, and a '
      'poll that changes nothing leaves it alone', (tester) async {
    await mount(tester, const Locale('en'));
    expect(shown(), contains(_englishBody));

    final loads = page().loadedHtml.length;
    await poll(tester);
    await poll(tester);
    expect(page().loadedHtml, hasLength(loads), reason: 'reloaded on a poll');

    const revised = '<h2>Print</h2><p>This is how you print.</p>';
    translations.upsert(_english(revised), partitionKey: 'en');
    await poll(tester);
    expect(shown(), contains(revised));
    expect(find.text(_notice), findsNothing);

    translations.delete(Translation.contentDocId('s1'), partitionKey: 'en');
    await poll(tester);
    expect(shown(), contains(_dutchBody));
    expect(shown(), contains('<html lang="nl">'));
    expect(find.text(_notice), findsOneWidget);

    // The notice came and went above the same WebView.
    expect(webviews.widgetsCreated, 1);
    expect(webviews.widgetBuilds, 1);
    await unmount(tester);
  });

  testWidgets('a changed Dutch lesson with no translation reloads the page', (
    tester,
  ) async {
    translations.delete(Translation.contentDocId('s1'), partitionKey: 'en');
    await mount(tester, const Locale('en'));
    expect(shown(), contains(_dutchBody));

    const revised = '<h2>Print</h2><p>Zo druk je iets af.</p>';
    content.upsert(Content(id: 's1', title: 'Print', body: revised).toMap());
    await poll(tester);
    expect(shown(), contains(revised));
    expect(find.text(_notice), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the header names the root goal in the app language: the '
      'Dutch title until it has a translation, then the translation; Dutch '
      'again in Nederlands (#210)', (tester) async {
    await mount(tester, const Locale('en'));
    expect(find.text('BASICS'), findsOneWidget);

    translations.upsert(
      Translation.goal(
        language: 'en',
        goalId: 'r1',
        title: 'Getting started',
        description: '',
        sourceHash: goalSourceHash(root),
      ).toMap(),
      partitionKey: 'en',
    );
    await poll(tester);
    expect(find.text('GETTING STARTED'), findsOneWidget);
    expect(find.text('BASICS'), findsNothing);

    await switchTo(tester, const Locale('nl'));
    expect(find.text('BASICS'), findsOneWidget);
    expect(find.text('GETTING STARTED'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a lesson not in the content cache yet is shown in the app '
      'language too, and follows its translation', (tester) async {
    await mount(tester, const Locale('en'), cached: false);
    expect(shown(), contains(_englishBody));
    expect(shown(), contains('<html lang="en">'));

    const revised = '<h2>Print</h2><p>This is how you print.</p>';
    translations.upsert(_english(revised), partitionKey: 'en');
    await poll(tester);
    expect(shown(), contains(revised));

    translations.delete(Translation.contentDocId('s1'), partitionKey: 'en');
    await poll(tester);
    expect(shown(), contains(_dutchBody));
    expect(find.text(_notice), findsOneWidget);

    await unmount(tester);
  });
}
