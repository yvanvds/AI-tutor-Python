// End-to-end (#208): the teacher edits a lesson per language on the
// Lesinhoud page. The toolbar picks Nederlands (the source) or English; the
// title, the editor, the preview and Upload work on the language picked.
// Saving in English writes the lesson's translation to `translations`, made
// from the Dutch lesson as stored, and leaves `content` alone; saving in
// Dutch leaves the translation alone and makes it stale, which the tree and
// the goal editor's Lesinhoud row then show. Upload warns when the file's
// `<html lang>` is not the language picked; switching language with unsaved
// changes asks first; a translation can be deleted on its own.
//
// Real app, real navigation, real Lesinhoud and goals pages, real
// ContentService / TranslationService over the in-memory Cosmos, and the
// preview in the real Windows WebView. Only the OS file dialog is faked
// (the picked file is read from the real disk). Which lesson the preview
// shows is read from what the page asks the (scripted) runner to run: each
// language's lesson has its own live example.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/lesson_translation.dart -d windows

import 'dart:io';

import 'package:ai_tutor_python/features/goals/editor/goal_form.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_file_picker.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// The Python in the English lesson's live example — distinct from the
/// Dutch lesson's `kLessonExampleCode`, so the runner tells them apart.
const String kEnglishExampleCode = 'name = "Mira"\nprint("Hello", name)';

const String kEnglishBody =
    '<h2>Printing</h2>\n'
    '<p>This is how you show something on the screen.</p>\n'
    '<pre class="run"><code>$kEnglishExampleCode</code></pre>';

const String kEditedDutchBody = '$kLessonBody\n<p>Nog een zin.</p>';

const Key kCurrent = Key('translation-status-en-current');
const Key kStale = Key('translation-status-en-stale');

/// The seeded Dutch lesson, as `content` holds it.
final Content kDutch = Content(id: 's1', title: 'Print', body: kLessonBody);

Map<String, LessonRunResult> lessonResults() => {
  kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
  kEnglishExampleCode: const LessonRunResult(stdout: 'Hello Mira'),
};

/// Writes [html] to a temp file and returns its path.
String htmlFile(String name, String html) {
  final dir = Directory.systemTemp.createTempSync('lesson_translation_it_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsStringSync(html);
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openLesinhoud(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Lesson content'));
    await pumpUntilFound(tester, find.byType(LessonContentPage));
    await pumpUntilFound(tester, find.text('Print'));
  }

  /// The tree row of the subgoal "Print".
  Finder printRow() => find
      .ancestor(of: find.text('Print').first, matching: find.byType(Row))
      .first;

  Finder bodyField() =>
      find.byWidgetPredicate((w) => w is TextField && w.expands);

  String editorBody(WidgetTester tester) =>
      tester.widget<TextField>(bodyField()).controller!.text;

  /// The preview is the lesson whose live example is [code]: the last one
  /// the page asked to run.
  Future<void> previewShows(
    WidgetTester tester,
    AppHarness harness,
    String code,
  ) => pumpUntil(
    tester,
    () =>
        harness.lessonRunner.ran.isNotEmpty &&
        harness.lessonRunner.ran.last == code,
    timeout: const Duration(seconds: 30),
    reason: 'the preview with "$code" never loaded',
  );

  Future<void> pickLanguage(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets('English: Upload warns on a Dutch file and takes an English '
      'one, Save writes only the translation, and a Dutch edit marks it '
      'stale in the tree and the goal editor', (tester) async {
    final harness = AppHarness(
      identity: teacherIdentity,
      lessonResults: lessonResults(),
    );
    await harness.boot(tester);
    final content = harness.cosmos['content'];
    final translations = harness.cosmos['translations'];
    final dutchDoc = content.read('s1');

    await openLesinhoud(tester);
    await tester.tap(find.text('Print').first);
    await pumpUntil(
      tester,
      () => bodyField().evaluate().isNotEmpty && editorBody(tester).isNotEmpty,
      reason: 'the Dutch lesson never reached the editor',
    );
    await previewShows(tester, harness, kLessonExampleCode);

    // English: no translation yet.
    await pickLanguage(tester, 'English');
    await pumpUntilFound(
      tester,
      find.byKey(const Key('lesson-translation-none')),
    );
    expect(editorBody(tester), '');

    // A Dutch file: the warning, and Cancel keeps it out.
    FakeFilePicker(
      htmlFile(
        'print_nl.html',
        '<!DOCTYPE html>\n<html lang="nl">\n<head><title>Print</title>'
            '</head>\n<body>\n$kLessonBody\n</body>\n</html>\n',
      ),
    ).install();
    await tester.tap(find.text('Upload .html'));
    await pumpUntilFound(tester, find.text('This file is in another language'));
    await tester.tap(find.text('Cancel'));
    await pumpUntilGone(tester, find.text('This file is in another language'));
    expect(editorBody(tester), '');

    // An English file goes straight in, and the preview is the English
    // lesson in the real WebView.
    FakeFilePicker(
      htmlFile(
        'print_en.html',
        '<!DOCTYPE html>\n<html lang="en">\n<head><title>Printing</title>'
            '</head>\n<body>\n$kEnglishBody\n</body>\n</html>\n',
      ),
    ).install();
    await tester.tap(find.text('Upload .html'));
    await pumpUntil(
      tester,
      () => editorBody(tester) == kEnglishBody,
      reason: 'the English file never reached the editor',
    );
    expect(find.text('This file is in another language'), findsNothing);
    await previewShows(tester, harness, kEnglishExampleCode);
    expect(
      tester.widget<LessonHtmlView>(find.byType(LessonHtmlView)).language,
      'en',
    );

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Printing');
    await tester.pump();
    await tester.tap(find.text('Save *'));
    await pumpUntilFound(tester, find.text('Saved'));

    final stored = translations.read('content_s1', partitionKey: 'en');
    expect(stored, isNotNull);
    expect(stored!['title'], 'Printing');
    expect(stored['body'], kEnglishBody);
    expect(stored['sourceHash'], contentSourceHash(kDutch));
    expect(content.read('s1'), dutchDoc, reason: '`content` is not touched');
    // The tree has it at once: an English translation, up to date.
    await pumpUntilFound(
      tester,
      find.descendant(of: printRow(), matching: find.byKey(kCurrent)),
    );

    // Back to Dutch — nothing unsaved, so no question — and edit it.
    await pickLanguage(tester, 'Nederlands (source)');
    await pumpUntil(
      tester,
      () => editorBody(tester) == kLessonBody,
      reason: 'the Dutch lesson never came back',
    );
    expect(find.text('Discard unsaved changes?'), findsNothing);
    await tester.enterText(bodyField(), kEditedDutchBody);
    await tester.pump();
    await tester.tap(find.text('Save *'));
    await pumpUntil(
      tester,
      () => content.read('s1')!['body'] == kEditedDutchBody,
      reason: 'the Dutch lesson was never saved',
    );
    expect(
      translations.read('content_s1', partitionKey: 'en'),
      stored,
      reason: 'saving Dutch leaves the translation as it is',
    );
    await pumpUntilFound(
      tester,
      find.descendant(of: printRow(), matching: find.byKey(kStale)),
    );
    expect(find.byKey(kCurrent), findsNothing);

    // The goal editor's Lesinhoud row says the same.
    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Print'));
    await tester.tap(find.text('Print').first);
    await pumpUntilFound(
      tester,
      find.descendant(of: find.byType(GoalForm), matching: find.byKey(kStale)),
    );
    expect(
      find.byTooltip(
        'English translation: outdated, the Dutch text changed after it was '
        'translated',
      ),
      findsOneWidget,
    );

    await harness.dispose(tester);
  });

  testWidgets('switching language with unsaved changes asks first, and '
      'deleting the translation removes only the translation', (tester) async {
    final harness = AppHarness(
      identity: teacherIdentity,
      lessonResults: lessonResults(),
      extraDocs: {
        'translations': [
          Translation.content(
            language: 'en',
            contentId: 's1',
            title: 'Printing',
            body: kEnglishBody,
            sourceHash: contentSourceHash(kDutch),
          ).toMap(),
        ],
      },
    );
    await harness.boot(tester);
    final content = harness.cosmos['content'];
    final translations = harness.cosmos['translations'];
    final dutchDoc = content.read('s1');

    await openLesinhoud(tester);
    await pumpUntilFound(
      tester,
      find.descendant(of: printRow(), matching: find.byKey(kCurrent)),
    );
    await tester.tap(find.text('Print').first);
    await pumpUntil(
      tester,
      () => bodyField().evaluate().isNotEmpty && editorBody(tester).isNotEmpty,
      reason: 'the Dutch lesson never reached the editor',
    );

    await pickLanguage(tester, 'English');
    await pumpUntil(
      tester,
      () => editorBody(tester) == kEnglishBody,
      reason: 'the English lesson never reached the editor',
    );
    await previewShows(tester, harness, kEnglishExampleCode);

    // An unsaved change, then Dutch: the question first.
    await tester.enterText(bodyField(), '$kEnglishBody\n<p>More.</p>');
    await tester.pump();
    await pickLanguage(tester, 'Nederlands (source)');
    await pumpUntilFound(tester, find.text('Discard unsaved changes?'));
    await tester.tap(find.text('Keep editing'));
    await pumpUntilGone(tester, find.text('Discard unsaved changes?'));
    expect(editorBody(tester), '$kEnglishBody\n<p>More.</p>');

    await pickLanguage(tester, 'Nederlands (source)');
    await pumpUntilFound(tester, find.text('Discard and switch'));
    await tester.tap(find.text('Discard and switch'));
    await pumpUntil(
      tester,
      () => editorBody(tester) == kLessonBody,
      reason: 'the Dutch lesson never came back',
    );
    await previewShows(tester, harness, kLessonExampleCode);
    expect(
      translations.read('content_s1', partitionKey: 'en')!['body'],
      kEnglishBody,
      reason: 'discarding writes nothing',
    );

    // Delete the translation: only its doc goes.
    await pickLanguage(tester, 'English');
    await pumpUntilFound(
      tester,
      find.byKey(const Key('lesson-delete-translation')),
    );
    await tester.tap(find.byKey(const Key('lesson-delete-translation')));
    await pumpUntilFound(tester, find.text('Delete the English translation?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpUntilFound(tester, find.text('English translation deleted'));

    expect(translations.read('content_s1', partitionKey: 'en'), isNull);
    expect(content.read('s1'), dutchDoc);
    expect(harness.cosmos['goals'].read('s1')!['contentId'], 's1');
    expect(find.byKey(const Key('lesson-translation-none')), findsOneWidget);
    await pumpUntilGone(
      tester,
      find.descendant(of: printRow(), matching: find.byKey(kCurrent)),
    );

    await harness.dispose(tester);
  });
}
