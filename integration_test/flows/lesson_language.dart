// End-to-end (#207): the theory page is in the language the student picked
// in Options. Sam's app runs in English (the harness pins an en-US desktop).
// With an English translation of the lesson the page is the translation,
// and a question typed on it (#132) goes out with the English page — the
// text on Sam's screen, not the Dutch source. Switching to Nederlands puts
// the Dutch lesson back. Without a translation the page is the Dutch lesson
// under a short notice that says so, until a translation arrives: then the
// page turns English on the next poll and the notice goes.
//
// Real app, real navigation, real Options page, real theory view over the
// real Windows WebView, real TranslationService polling the (in-memory)
// `translations` container, real chat → TutorService → request assembly.
// Only the model is scripted. Which lesson the WebView shows is read from
// what the page itself asks the runner to run: each language's lesson has
// its own live example.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/lesson_language.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kNotice =
    'This lesson is not available in English yet, so it is shown in Dutch.';

/// The Python inside the English lesson's live-preview block — distinct
/// from the Dutch lesson's `kLessonExampleCode`, so the runner tells the
/// two pages apart.
const String kEnglishExampleCode = 'name = "Mira"\nprint("Hello", name)';

const String kEnglishBody =
    '<h2>Printing</h2>'
    '<p>This is how you show something on the screen.</p>'
    '<pre class="run"><code>$kEnglishExampleCode</code></pre>';

/// The seeded lesson's English translation, made from its current Dutch
/// text.
Map<String, dynamic> englishTranslation() => Translation.content(
  language: 'en',
  contentId: 's1',
  title: 'Printing',
  body: kEnglishBody,
  sourceHash: contentSourceHash(
    Content(id: 's1', title: 'Print', body: kLessonBody),
  ),
).toMap();

String answerReply(String text) =>
    llmEnvelope(text: text, meta: '{"type":"answer"}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Map<String, LessonRunResult> lessonResults() => {
    kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
    kEnglishExampleCode: const LessonRunResult(stdout: 'Hello Mira'),
  };

  /// The page on screen is the one with [code] in it: the last example the
  /// page asked to run. A page shown in Dutch until the translations came
  /// back may have asked first.
  Future<void> lessonOnScreen(
    WidgetTester tester,
    AppHarness harness,
    String code,
  ) => pumpUntil(
    tester,
    () =>
        harness.lessonRunner.ran.isNotEmpty &&
        harness.lessonRunner.ran.last == code,
    timeout: const Duration(seconds: 30),
    reason: 'the lesson page with "$code" never loaded',
  );

  Future<void> openLesson(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
  }

  Finder composer() => find.descendant(
    of: find.byType(ComposerIdle),
    matching: find.byType(TextField),
  );

  Future<void> typeInChat(WidgetTester tester, String text) async {
    await pumpUntilFound(tester, composer());
    await tester.tap(composer());
    await tester.pump();
    await tester.enterText(composer(), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
  }

  testWidgets('in English the theory page is the English lesson and a '
      'question about it goes out with the English page; in Nederlands it '
      'is the Dutch lesson', (tester) async {
    final llm = ScriptedLlm([
      answerReply('The comma puts a space between the two values.'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'translations': [englishTranslation()],
      },
      lessonResults: lessonResults(),
    );
    await harness.boot(tester);
    await openLesson(tester);

    await lessonOnScreen(tester, harness, kEnglishExampleCode);
    // It stays English: the Dutch page does not come back on a poll.
    await tester.pump(const Duration(seconds: 6));
    expect(harness.lessonRunner.ran.last, kEnglishExampleCode);
    expect(find.text(kNotice), findsNothing);

    // A question about the page carries the page as Sam reads it.
    await typeInChat(tester, 'Why is there a comma?');
    await pumpUntil(
      tester,
      () => llm.sends == 1,
      timeout: const Duration(seconds: 30),
      reason: 'the question never went out',
    );
    final question = jsonDecode(llm.sentInputs.single) as Map<String, dynamic>;
    expect(question['request_type'], 'content_question');
    expect(question['content_title'], 'Printing');
    final page = question['content'] as String;
    expect(page, contains('## Printing'));
    expect(page, contains('This is how you show something on the screen.'));
    expect(page, contains('```\n$kEnglishExampleCode\n```'));
    expect(page, isNot(contains('Zo toon je iets op het scherm.')));
    await pumpUntilFound(
      tester,
      find.textContaining('puts a space between', findRichText: true),
    );

    // Nederlands in Options, back to the session: the Dutch lesson.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Sessie'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await lessonOnScreen(tester, harness, kLessonExampleCode);
    expect(
      find.byKey(const Key('explain-translation-missing')),
      findsNothing,
      reason: 'Dutch is the language lessons are written in',
    );

    await harness.dispose(tester);
  });

  testWidgets('without an English translation the page is the Dutch lesson '
      'under a notice, until a translation arrives', (tester) async {
    final harness = AppHarness(lessonResults: lessonResults());
    await harness.boot(tester);
    await openLesson(tester);

    await lessonOnScreen(tester, harness, kLessonExampleCode);
    await pumpUntilFound(tester, find.text(kNotice));
    // Above the page, in the real layout, not over it.
    expect(
      tester.getBottomLeft(find.text(kNotice)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(LessonHtmlView)).dy),
    );
    expect(
      tester.getSize(find.byType(LessonHtmlView)).height,
      greaterThan(300),
    );

    // The teacher adds the translation: the next poll brings it in.
    harness.cosmos['translations'].upsert(
      englishTranslation(),
      partitionKey: 'en',
    );
    await lessonOnScreen(tester, harness, kEnglishExampleCode);
    await pumpUntilGone(tester, find.text(kNotice));

    await harness.dispose(tester);
  });
}
