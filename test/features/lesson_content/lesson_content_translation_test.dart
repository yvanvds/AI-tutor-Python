// Issue #208 — the Lesinhoud page edits a lesson per language. The toolbar
// picks Nederlands (the source) or English; title, editor, preview and
// Upload work on the language picked. Saving in Dutch writes `content` as
// before; saving in English writes `content_${id}` in `translations`, with
// the hash of the Dutch lesson as stored, and leaves `content` alone. Upload
// warns when the file's `<html lang>` is another language; switching
// language with unsaved changes asks first; a translation can be deleted on
// its own; the tree marks which translations a lesson has and which are
// stale.
//
// Mounts the real page over the real GoalsService / ContentService /
// ModuleService / TranslationService, each on an in-memory Cosmos, with a
// fake WebView platform under the preview and a fake file picker under
// Upload (an OS dialog no test can click; the file is read from disk).

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_file_picker.dart';
import '../../helpers/fake_lesson_code_runner.dart';
import '../../helpers/fake_webview_platform.dart';
import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

const _dutchTitle = 'Printen';
const _dutchBody = '<p>Zo toon je iets op het scherm.</p>';
const _englishBody = '<p>This is how you show something.</p>';

final _dutch = Content(id: 's1', title: _dutchTitle, body: _dutchBody);

/// How [upload] steps real time while the picked file is read, and how long
/// it waits in all before it gives up (#213).
const _uploadStep = Duration(milliseconds: 20);
const _uploadTimeout = Duration(seconds: 20);

const _staleNotice =
    'Outdated: the Dutch lesson changed after this English translation was '
    'made. Update it and save it again.';
const _noneNotice =
    'This lesson has no English translation yet. Students who use the app '
    'in English see the Dutch lesson.';

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

/// The English translation of the seeded lesson, made from [from].
Map<String, dynamic> _english({Content? from, String body = _englishBody}) =>
    Translation.content(
      language: 'en',
      contentId: 's1',
      title: 'Printing',
      body: body,
      sourceHash: contentSourceHash(from ?? _dutch),
    ).toMap();

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos content;
  late InMemoryCosmos modules;
  late InMemoryCosmos translations;
  late FakeWebViewPlatform webviews;

  setUp(() {
    webviews = FakeWebViewPlatform.install();
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Basics'),
      _goal(id: 's1', title: 'Print', parentId: 'r1', contentId: 's1'),
      _goal(id: 's2', title: 'Variables', parentId: 'r1', order: 2000),
    ]);
    content = InMemoryCosmos([
      {..._dutch.toMap(), 'type': 'content'},
    ]);
    modules = InMemoryCosmos([
      {
        'id': 'python-basics',
        'type': 'module',
        'title': 'Python basics',
        'order': 0,
      },
    ]);
    translations = InMemoryCosmos.partitioned('language');
  });

  Widget buildApp(CosmosContainer translationsContainer) => ProviderScope(
    overrides: [
      goalsServiceProvider.overrideWithValue(
        GoalsService(container: goals.container),
      ),
      contentServiceProvider.overrideWith(
        () => ContentService(container: content.container),
      ),
      moduleServiceProvider.overrideWith(
        () => ModuleService(container: modules.container),
      ),
      translationServiceProvider.overrideWithValue(
        TranslationService(container: translationsContainer),
      ),
      lessonCodeRunnerProvider.overrideWithValue(FakeLessonCodeRunner()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: LessonContentPage()),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    CosmosContainer? translationsContainer,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildApp(translationsContainer ?? translations.container),
    );
    // Bootstrap (ensureDefaultModule + backfill), then the first polls.
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  /// The subgoal row in the tree: goal title over the lesson title.
  Finder subgoalRow(String goalTitle) => find
      .ancestor(
        of: find.text(goalTitle),
        matching: find.byType(GestureDetector),
      )
      .first;

  Finder badge(String goalTitle, TranslationStatus status) => find.descendant(
    of: subgoalRow(goalTitle),
    matching: find.byKey(Key('translation-status-en-${status.name}')),
  );

  Finder bodyField() =>
      find.byWidgetPredicate((w) => w is TextField && w.expands);
  Finder titleField() => find.widgetWithText(TextField, 'Title');

  String editorBody(WidgetTester tester) =>
      tester.widget<TextField>(bodyField()).controller!.text;
  String editorTitle(WidgetTester tester) =>
      tester.widget<TextField>(titleField()).controller!.text;

  Future<void> select(WidgetTester tester, String goalTitle) async {
    await tester.tap(find.text(goalTitle));
    await settle(tester);
  }

  Future<void> pickLanguage(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save *'));
    await settle(tester);
  }

  bool warned() =>
      find.text('This file is in another language').evaluate().isNotEmpty;

  /// Taps Upload and waits until [until] holds: until the page has acted on
  /// the picked file — the warning is up, or the editor holds the file.
  ///
  /// The page reads that file from disk for real, which the fake clock of a
  /// widget test does not advance, so this lets real time pass in small
  /// steps. It waits on the outcome, not on a fixed time: under a loaded
  /// full suite the read can take far longer than a fixed wait allowed
  /// (#213), and a test that went on before the read was done found no
  /// warning and left the file open for its tear-down to trip over. Once
  /// [until] holds the read is over and the file closed. Fails after
  /// [_uploadTimeout], saying what never happened.
  Future<void> upload(
    WidgetTester tester, {
    required String expecting,
    required bool Function() until,
  }) async {
    await tester.tap(find.text('Upload .html'));
    var waited = Duration.zero;
    while (!until()) {
      if (waited >= _uploadTimeout) {
        fail(
          'Upload: $expecting did not happen within '
          '${_uploadTimeout.inSeconds} s of real time',
        );
      }
      await tester.runAsync(() => Future<void>.delayed(_uploadStep));
      await tester.pump();
      waited += _uploadStep;
    }
    await settle(tester);
  }

  String writeHtml(String html) {
    final dir = Directory.systemTemp.createTempSync('lesson_upload_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}lesson.html');
    file.writeAsStringSync(html);
    return file.path;
  }

  testWidgets('saving in English writes only the translation, made from the '
      'Dutch lesson as stored', (tester) async {
    await mount(tester);
    final dutchDoc = Map.of(content['s1']!);

    await select(tester, 'Print');
    await pickLanguage(tester, 'English');
    // No translation yet: an empty editor, and a notice that says so.
    expect(editorBody(tester), '');
    expect(editorTitle(tester), '');
    expect(find.text(_noneNotice), findsOneWidget);
    expect(badge('Print', TranslationStatus.current), findsNothing);

    await tester.enterText(titleField(), 'Printing');
    await tester.enterText(bodyField(), _englishBody);
    await tester.pump();
    // The preview shows the English lesson, marked as English.
    final preview = tester.widget<LessonHtmlView>(find.byType(LessonHtmlView));
    expect(preview.fragment, _englishBody);
    expect(preview.language, 'en');
    await settle(tester);
    expect(
      webviews.controllers.last.currentHtml,
      allOf(contains('<html lang="en">'), contains(_englishBody)),
    );

    await save(tester);

    final stored = translations['en/content_s1'];
    expect(stored, isNotNull);
    expect(stored!['language'], 'en');
    expect(stored['kind'], 'content');
    expect(stored['refId'], 's1');
    expect(stored['title'], 'Printing');
    expect(stored['body'], _englishBody);
    expect(stored['sourceHash'], contentSourceHash(_dutch));
    expect(stored['updatedAt'], isNotNull);
    expect(content['s1'], dutchDoc, reason: '`content` is not touched');
    expect(content.docs, hasLength(1));
    expect(find.text('Saved'), findsOneWidget);
    // Saved: nothing unsaved, the notice gone, the tree shows the
    // translation at once.
    expect(find.text('Save *'), findsNothing);
    expect(find.text(_noneNotice), findsNothing);
    expect(badge('Print', TranslationStatus.current), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('saving in Dutch leaves the translation as it is, and the tree '
      'marks it stale at once', (tester) async {
    translations.upsert(_english(), partitionKey: 'en');
    await mount(tester);
    final englishDoc = Map.of(translations['en/content_s1']!);
    expect(badge('Print', TranslationStatus.current), findsOneWidget);

    await select(tester, 'Print');
    expect(editorBody(tester), _dutchBody);
    await tester.enterText(bodyField(), '<p>Zo toon je tekst.</p>');
    await tester.pump();
    await save(tester);

    expect(content['s1']!['body'], '<p>Zo toon je tekst.</p>');
    expect(translations['en/content_s1'], englishDoc);
    expect(translations.docs, hasLength(1));
    expect(badge('Print', TranslationStatus.current), findsNothing);
    expect(badge('Print', TranslationStatus.stale), findsOneWidget);
    expect(
      find.byTooltip(
        'English translation: outdated, the Dutch text changed after it was '
        'translated',
      ),
      findsOneWidget,
    );

    // The English editor says so too.
    await pickLanguage(tester, 'English');
    expect(editorBody(tester), _englishBody);
    expect(find.text(_staleNotice), findsOneWidget);

    // Saving the translation again makes it current: made from the Dutch
    // lesson as it is now.
    await tester.enterText(bodyField(), '<p>This is how you show text.</p>');
    await tester.pump();
    await save(tester);
    expect(
      translations['en/content_s1']!['sourceHash'],
      contentSourceHash(
        Content(id: 's1', title: _dutchTitle, body: '<p>Zo toon je tekst.</p>'),
      ),
    );
    expect(find.text(_staleNotice), findsNothing);
    expect(badge('Print', TranslationStatus.current), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the status "stale" follows a Dutch edit made elsewhere, on the '
      'next poll', (tester) async {
    translations.upsert(_english(), partitionKey: 'en');
    await mount(tester);
    expect(badge('Print', TranslationStatus.current), findsOneWidget);

    content.upsert({...content['s1']!, 'body': '<p>Anders.</p>'});
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);

    expect(badge('Print', TranslationStatus.stale), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Upload with a <html lang> that does not match the language '
      'picked warns first', (tester) async {
    await mount(tester);
    await select(tester, 'Print');
    await pickLanguage(tester, 'English');

    FakeFilePicker(
      writeHtml(
        '<!DOCTYPE html>\n<html lang="nl">\n<head><title>Printen</title>'
        '</head>\n<body>\n<p>Nederlands</p>\n</body>\n</html>',
      ),
    ).install();
    await upload(tester, expecting: 'the warning', until: warned);

    expect(find.text('This file is in another language'), findsOneWidget);
    expect(
      find.text(
        'The file is marked as Nederlands (lang="nl"), but you are editing '
        'the English lesson. Put it in this lesson anyway?',
      ),
      findsOneWidget,
    );
    // Cancel leaves the editor as it was.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('This file is in another language'), findsNothing);
    expect(editorBody(tester), '');

    // Going ahead puts the file's body in the English lesson.
    await upload(tester, expecting: 'the warning, again', until: warned);
    await tester.tap(find.text('Upload anyway'));
    await settle(tester);
    expect(editorBody(tester), '<p>Nederlands</p>');

    await unmount(tester);
  });

  testWidgets('Upload of a file in the language picked, or one that does not '
      'say, goes straight in', (tester) async {
    await mount(tester);
    await select(tester, 'Print');
    await pickLanguage(tester, 'English');

    FakeFilePicker(
      writeHtml('<html lang="en-GB"><body><p>British</p></body></html>'),
    ).install();
    await upload(
      tester,
      expecting: 'the en-GB file in the editor',
      until: () => editorBody(tester) == '<p>British</p>',
    );
    expect(find.text('This file is in another language'), findsNothing);
    expect(editorBody(tester), '<p>British</p>');

    FakeFilePicker(writeHtml('<p>Just a fragment</p>')).install();
    await upload(
      tester,
      expecting: 'the fragment in the editor',
      until: () => editorBody(tester) == '<p>Just a fragment</p>',
    );
    expect(find.text('This file is in another language'), findsNothing);
    expect(editorBody(tester), '<p>Just a fragment</p>');

    // In Dutch, an English file is the mismatch.
    await pickLanguage(tester, 'Nederlands (source)');
    await tester.tap(find.text('Discard and switch'));
    await settle(tester);
    FakeFilePicker(
      writeHtml('<html lang="en"><body><p>English</p></body></html>'),
    ).install();
    await upload(
      tester,
      expecting: 'the warning for an English file in Dutch',
      until: warned,
    );
    expect(find.text('This file is in another language'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(editorBody(tester), _dutchBody);

    await unmount(tester);
  });

  testWidgets('switching language with unsaved changes asks first', (
    tester,
  ) async {
    translations.upsert(_english(), partitionKey: 'en');
    await mount(tester);
    await select(tester, 'Print');

    // Nothing changed: no question.
    await pickLanguage(tester, 'English');
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(editorBody(tester), _englishBody);
    expect(editorTitle(tester), 'Printing');

    await tester.enterText(bodyField(), '<p>Changed</p>');
    await tester.pump();
    await pickLanguage(tester, 'Nederlands (source)');
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    expect(
      find.text(
        'The English lesson has changes that are not saved. Switching to '
        'Nederlands discards them.',
      ),
      findsOneWidget,
    );

    // Keep editing: still English, the change still there.
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(editorBody(tester), '<p>Changed</p>');
    expect(
      tester.widget<LessonHtmlView>(find.byType(LessonHtmlView)).language,
      'en',
    );

    // Discard: the Dutch lesson, and nothing was written.
    await pickLanguage(tester, 'Nederlands (source)');
    await tester.tap(find.text('Discard and switch'));
    await settle(tester);
    expect(editorBody(tester), _dutchBody);
    expect(editorTitle(tester), _dutchTitle);
    expect(translations['en/content_s1']!['body'], _englishBody);
    expect(
      tester.widget<LessonHtmlView>(find.byType(LessonHtmlView)).language,
      'nl',
    );

    await unmount(tester);
  });

  testWidgets('deleting the translation removes only the translation', (
    tester,
  ) async {
    translations.upsert(_english(), partitionKey: 'en');
    await mount(tester);
    final dutchDoc = Map.of(content['s1']!);
    await select(tester, 'Print');

    // Dutch has no such action; Unlink is the Dutch lesson's.
    expect(find.byKey(const Key('lesson-delete-translation')), findsNothing);
    expect(find.text('Unlink'), findsOneWidget);

    await pickLanguage(tester, 'English');
    expect(find.text('Unlink'), findsNothing);
    await tester.tap(find.byKey(const Key('lesson-delete-translation')));
    await settle(tester);
    expect(find.text('Delete the English translation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    expect(translations['en/content_s1'], isNotNull);

    await tester.tap(find.byKey(const Key('lesson-delete-translation')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(translations['en/content_s1'], isNull);
    expect(content['s1'], dutchDoc);
    expect(goals['s1']!['contentId'], 's1');
    expect(find.text('English translation deleted'), findsOneWidget);
    expect(editorBody(tester), '');
    expect(find.text(_noneNotice), findsOneWidget);
    expect(badge('Print', TranslationStatus.current), findsNothing);

    await unmount(tester);
  });

  testWidgets('a subgoal without a Dutch lesson has nothing to translate', (
    tester,
  ) async {
    await mount(tester);
    await pickLanguage(tester, 'English');
    await select(tester, 'Variables');

    expect(
      find.byKey(const Key('lesson-translation-needs-source')),
      findsOneWidget,
    );
    expect(bodyField(), findsNothing);
    final upload = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Upload .html'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(upload.onPressed, isNull);

    // Dutch is where it starts.
    await pickLanguage(tester, 'Nederlands (source)');
    expect(editorTitle(tester), 'Variables');
    expect(editorBody(tester), '');

    // The subgoal's title stands in for a new lesson's; that is not an
    // edit to lose, so leaving for English does not ask.
    await pickLanguage(tester, 'English');
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(
      find.byKey(const Key('lesson-translation-needs-source')),
      findsOneWidget,
    );

    // A body typed into the new Dutch lesson is.
    await pickLanguage(tester, 'Nederlands (source)');
    await tester.enterText(bodyField(), '<p>Nieuw</p>');
    await tester.pump();
    await pickLanguage(tester, 'English');
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(editorBody(tester), '<p>Nieuw</p>');

    await unmount(tester);
  });

  testWidgets('without a translations container, saving a translation says '
      'what to do and writes nothing', (tester) async {
    final missing = UnprovisionedCosmos('translations');
    await mount(tester, translationsContainer: missing.container);
    final dutchDoc = Map.of(content['s1']!);
    await select(tester, 'Print');
    await pickLanguage(tester, 'English');

    await tester.enterText(bodyField(), _englishBody);
    await tester.pump();
    await save(tester);

    expect(
      find.text(
        'Translations cannot be saved yet: the Cosmos container '
        '`translations` does not exist. Create it with partition key '
        '`/language` (README, step 3).',
      ),
      findsOneWidget,
    );
    expect(content['s1'], dutchDoc);
    // Still unsaved.
    expect(find.text('Save *'), findsOneWidget);

    await unmount(tester);
  });

  group('htmlLangAttribute', () {
    test('reads the lang of the <html> element', () {
      expect(htmlLangAttribute('<!DOCTYPE html>\n<html lang="nl">'), 'nl');
      expect(htmlLangAttribute("<HTML LANG='en-GB'>"), 'en-GB');
      expect(htmlLangAttribute('<html class="x" lang=en>'), 'en');
      expect(htmlLangAttribute('<html\n  lang = "fr" >'), 'fr');
    });

    test('is null when the document does not say', () {
      expect(htmlLangAttribute('<p>fragment</p>'), isNull);
      expect(htmlLangAttribute('<html><body></body></html>'), isNull);
      expect(htmlLangAttribute('<html lang="">'), isNull);
      // Another element's lang is not the document's.
      expect(htmlLangAttribute('<html><p lang="en">x</p></html>'), isNull);
      expect(htmlLangAttribute('<html data-lang="en">'), isNull);
    });
  });
}
