// The screenshots of the website (#290), made from the running app.
//
// Not a test of the app and not part of the integration suite: it is not in
// `integration_test/app_test.dart`, it lives outside `flows/` (which CI runs
// file by file when the aggregated run aborts), and nothing in CI runs it.
// Run it by hand when a screen the site shows has changed visibly:
//
//   flutter test integration_test/screenshots/site_screenshots.dart -d windows
//
// One screen, or one language, with `--name` (a regular expression), e.g.
// `--name practice` or `--name "\(en"`. The images land in
// `public/screenshots/<lang>/<screen>.png` of the checkout the run starts in
// (`--dart-define=SITE_SCREENSHOTS_DIR=…` writes them elsewhere); see the
// README for when to run it.
//
// Each screen boots the real app through the integration harness — the real
// shell, pages, services and navigation — with Cosmos in memory and seeded
// with the invented demo class of `demo_seed.dart`, the model scripted
// (`ScriptedLlm`) and Python scripted (`FakePyRunner`, the lesson runner).
// Then it walks to the screen the way a student or the teacher would, and
// writes what the window shows: every screen dark (the theme the app starts
// in), in Dutch and in English, and the Practice screen also light, for the
// site's large image that follows the visitor's theme.
//
// The window is 1440 × 900 logical pixels; the images are written at
// [_pixelRatio] times that — 2160 × 1350 by default
// (`--dart-define=SITE_SCREENSHOT_PIXEL_RATIO=…`). Flutter only encodes PNG,
// and every refresh lands in git history, so the ratio and `png_encoder.dart`
// are what keep the set small: about 170 KB an image, under 5 MB in all.
//
// Turtle and matplotlib draw in a window of their own, outside Flutter, and
// cannot be taken this way.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/goals/child_row.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/goals/root_row.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/questions/questions_page.dart';
import 'package:ai_tutor_python/features/reports/reports_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/widgets/output_panel.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/content_language.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:py_runner/py_runner.dart';

import '../../test/helpers/fake_py_runner.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import 'demo_seed.dart';
import 'png_encoder.dart';

/// The window every screen is taken at, in logical pixels.
const Size kSiteWindowSize = Size(1440, 900);

/// Image pixels per logical pixel.
final double _pixelRatio = double.parse(
  const String.fromEnvironment(
    'SITE_SCREENSHOT_PIXEL_RATIO',
    defaultValue: '1.5',
  ),
);

/// `public/screenshots` of the checkout this runs in, or the directory
/// `--dart-define=SITE_SCREENSHOTS_DIR=…` names.
Directory _outputDir() {
  const named = String.fromEnvironment('SITE_SCREENSHOTS_DIR');
  if (named.isNotEmpty) return Directory(named);
  var dir = Directory.current.absolute;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'public')).existsSync()) {
      return Directory(p.join(dir.path, 'public', 'screenshots'));
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'no checkout above ${Directory.current.path}; pass '
        '--dart-define=SITE_SCREENSHOTS_DIR=<dir>',
      );
    }
    dir = parent;
  }
}

/// Pumps real frames for [duration], so what is animating in has arrived
/// and a tap's mark on the test view has faded.
Future<void> _settle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 1200),
]) async {
  final until = DateTime.now().add(duration);
  while (DateTime.now().isBefore(until)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Writes what the window shows to `<lang>/<name>.png` under [_outputDir].
///
/// The whole view, not one repaint boundary: dialogs, drawers, notices and
/// the level-up moment sit in routes and overlays of their own. The root
/// layer paints in physical pixels, so its bounds are the physical size and
/// the ratio is divided by the device's.
Future<void> _capture(
  WidgetTester tester,
  DemoLanguage lang,
  String name,
) async {
  await _settle(tester);
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  final view = tester.view;
  final image = await layer.toImage(
    Offset.zero & view.physicalSize,
    pixelRatio: _pixelRatio / view.devicePixelRatio,
  );
  final (width, height) = (image.width, image.height);
  final rgba = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  final png = encodeOpaquePng(rgba!.buffer.asUint8List(), width, height);
  final file = File(p.join(_outputDir().path, lang.code, '$name.png'));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png);
  debugPrint(
    'site screenshot: ${file.path} ($width x $height, ${png.length} bytes)',
  );
}

/// Boots the app as [identity] in [lang], on the demo class.
Future<AppHarness> _boot(
  WidgetTester tester,
  DemoLanguage lang, {
  AccountIdentity identity = demoStudent,
  ScriptedLlm? llm,
  PyRunner? pyRunner,
  Brightness brightness = Brightness.dark,
}) async {
  final harness = AppHarness(
    identity: identity,
    llm: llm,
    pyRunner: pyRunner,
    prefs: {'app_locale': lang.code},
    windowSize: kSiteWindowSize,
    systemBrightness: brightness,
    // The instructions editor is a developer's tool, not the teacher's.
    developerTools: false,
    extraDocs: demoDocs(lang, now: DateTime.now()),
    lessonResults: {
      demoLessonCode(lang): LessonRunResult(stdout: demoLessonOutput(lang)),
    },
  );
  await harness.boot(tester);
  // The language is the stored choice, read after the first frame.
  await pumpUntilFound(tester, find.byTooltip(_l(lang).sidebar_section_map));
  return harness;
}

AppLocalizations _l(DemoLanguage lang) =>
    lookupAppLocalizations(Locale(lang.code));

Future<void> _idle(WidgetTester tester, AppHarness harness) => pumpUntil(
  tester,
  () => harness.container.read(tutorServiceProvider) == TutorState.idle,
  timeout: const Duration(seconds: 30),
  reason: 'the tutor never came back',
);

/// Learning path → "Continue" on the goal in progress. The student is a
/// third into the subgoal, so it opens on practice (`_continueRoot`), which
/// asks for an exercise.
Future<void> _continueLearning(WidgetTester tester, DemoLanguage lang) async {
  final l = _l(lang);
  await tester.tap(find.byTooltip(l.sidebar_section_map));
  await pumpUntilFound(tester, find.byType(LeerpadPage));
  await pumpUntilFound(tester, find.text(l.leerpad_card_button_continue));
  await tester.tap(find.text(l.leerpad_card_button_continue));
  await pumpUntil(
    tester,
    () =>
        find.byType(PracticeView).evaluate().isNotEmpty ||
        find.byType(QuizView).evaluate().isNotEmpty,
    reason: '"Continue" never opened the practice',
  );
}

/// The practice screen: a write-code exercise, the student's attempt run,
/// and the tutor's hint in the chat.
Future<void> _practice(
  WidgetTester tester,
  DemoLanguage lang, {
  required Brightness brightness,
}) async {
  final l = _l(lang);
  final python = FakePyRunner();
  addTearDown(python.dispose);
  final llm = ScriptedLlm([
    llmEnvelope(
      text: lang.pick(
        'Een winkel geeft **10% korting** vanaf een bedrag van 50 euro. '
            'Schrijf een programma dat voor `bedrag = 64` toont hoeveel '
            'korting je krijgt en hoeveel je moet betalen.',
        'A shop gives **10% off** from an amount of 50 euros. Write a '
            'program that shows, for `amount = 64`, how much discount you '
            'get and how much you have to pay.',
      ),
      meta: '{"type":"write_code"}',
    ),
    llmEnvelope(
      text: lang.pick(
        'De korting reken je al goed uit. Kijk nu naar de laatste regel: '
            'welk bedrag toon je daar? Trek je de korting ergens af?',
        'You already work out the discount correctly. Now look at the last '
            'line: which amount do you show there? Do you take the discount '
            'off anywhere?',
      ),
      meta: '{"type":"hint"}',
    ),
  ]);
  final harness = await _boot(
    tester,
    lang,
    llm: llm,
    pyRunner: python,
    brightness: brightness,
  );

  await _continueLearning(tester, lang);
  await pumpUntilFound(tester, find.byType(PracticeView));
  await pumpUntil(
    tester,
    () => llm.sends == 1,
    timeout: const Duration(seconds: 30),
    reason: 'no exercise was asked for',
  );
  await _idle(tester, harness);

  harness.container
      .read(codeServiceProvider(SessionMode.practice))
      .setText(
        lang.pick(
          'bedrag = 64\n'
              '\n'
              'if bedrag > 50:\n'
              '    korting = bedrag * 0.1\n'
              '    print("Korting:", korting)\n'
              '\n'
              'print("Te betalen:", bedrag)\n',
          'amount = 64\n'
              '\n'
              'if amount > 50:\n'
              '    discount = amount * 0.1\n'
              '    print("Discount:", discount)\n'
              '\n'
              'print("To pay:", amount)\n',
        ),
      );
  await tester.pump();
  await tester.tap(find.text(l.session_runControls_button_run));
  await pumpUntil(tester, () => python.handles.isNotEmpty);
  python.lastHandle
    ..emitStdout(
      lang.pick(
        'Korting: 6.4\nTe betalen: 64\n',
        'Discount: 6.4\nTo pay: 64\n',
      ),
    )
    ..complete(
      const RunResult(
        status: RunStatus.ok,
        duration: Duration(milliseconds: 41),
      ),
    );
  await pumpUntilFound(
    tester,
    find.descendant(
      of: find.byType(OutputPanel),
      matching: find.textContaining('6.4', findRichText: true),
    ),
  );

  await tester.tap(find.byTooltip(l.session_runControls_tooltip_askHint));
  await pumpUntil(
    tester,
    () => llm.sends == 2,
    timeout: const Duration(seconds: 30),
    reason: 'the hint was never asked for',
  );
  await _idle(tester, harness);

  await _capture(
    tester,
    lang,
    brightness == Brightness.light ? 'practice-light' : 'practice',
  );
  await harness.dispose(tester);
}

/// The question of the quiz screen: a multiple-choice question on the
/// subgoal the student is on.
String _quizPrompt(DemoLanguage lang) =>
    lang.pick('Wat toont dit programma?', 'What does this program print?');

String _quizReply(DemoLanguage lang) => llmEnvelope(
  text: _quizPrompt(lang),
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': lang.pick(
      'punten = 12\n\nif punten >= 10:\n    print("geslaagd")\n'
          'else:\n    print("niet geslaagd")\nprint("einde")',
      'points = 12\n\nif points >= 10:\n    print("passed")\n'
          'else:\n    print("failed")\nprint("done")',
    ),
    'options': [
      for (final option in [
        lang.pick('geslaagd\neinde', 'passed\ndone'),
        lang.pick('geslaagd', 'passed'),
        lang.pick('niet geslaagd\neinde', 'failed\ndone'),
        lang.pick('einde', 'done'),
      ])
        {'option': option},
    ],
    'correct': 'A',
  }),
);

/// Waits for [_quizReply] to be up in the quiz view.
Future<void> _quizUp(
  WidgetTester tester,
  AppHarness harness,
  DemoLanguage lang,
) async {
  await pumpUntilFound(tester, find.byType(QuizView));
  await pumpUntil(
    tester,
    () =>
        harness.container.read(activeMcqProvider)?.prompt == _quizPrompt(lang),
    timeout: const Duration(seconds: 30),
    reason: 'the question never reached the quiz',
  );
  await _idle(tester, harness);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The "DEBUG" ribbon of a debug build, which a release never shows.
  WidgetsApp.debugAllowBannerOverride = false;

  for (final lang in DemoLanguage.values) {
    final l = _l(lang);

    // ---- Student ------------------------------------------------------------

    testWidgets('practice (${lang.code}, dark)', (tester) async {
      await _practice(tester, lang, brightness: Brightness.dark);
    });

    testWidgets('practice (${lang.code}, light)', (tester) async {
      await _practice(tester, lang, brightness: Brightness.light);
    });

    testWidgets('explain (${lang.code})', (tester) async {
      final llm = ScriptedLlm([
        _quizReply(lang),
        llmEnvelope(
          text: lang.pick(
            'Omdat `print("Fijne dag!")` niet inspringt. Alleen de regels '
                'die inspringen onder `if` of `else` horen bij dat blok. Een '
                'regel die weer vooraan begint, staat buiten de if-else en '
                'loopt dus altijd, wat de temperatuur ook is.',
            'Because `print("Have a nice day!")` is not indented. Only the '
                'indented lines under `if` or `else` belong to that block. A '
                'line that starts at the left again is outside the if-else, '
                'so it always runs, whatever the temperature.',
          ),
          meta: '{"type":"answer"}',
        ),
      ]);
      final harness = await _boot(tester, lang, llm: llm);
      await _continueLearning(tester, lang);
      await _quizUp(tester, harness, lang);
      // The theory of the subgoal, from the mode switcher, and a question
      // about it in the chat.
      await tester.tap(find.text(l.session_mode_explain));
      await pumpUntilFound(tester, find.byType(ExplainView));
      await pumpUntil(
        tester,
        () => harness.lessonRunner.ran.contains(demoLessonCode(lang)),
        timeout: const Duration(seconds: 30),
        reason: 'the lesson never ran its live example',
      );
      final composer = find.descendant(
        of: find.byType(ComposerIdle),
        matching: find.byType(TextField),
      );
      await pumpUntilFound(tester, composer);
      await tester.tap(composer);
      await tester.pump();
      await tester.enterText(
        composer,
        lang.pick(
          'Waarom loopt de laatste regel altijd?',
          'Why does the last line always run?',
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await pumpUntil(
        tester,
        () => llm.sends == 2,
        timeout: const Duration(seconds: 30),
        reason: 'the question was never sent',
      );
      await _idle(tester, harness);
      // The page fills the output pane after the run answered.
      await _settle(tester, const Duration(seconds: 2));
      await _capture(tester, lang, 'explain');
      await harness.dispose(tester);
    });

    testWidgets('quiz (${lang.code})', (tester) async {
      final harness = await _boot(
        tester,
        lang,
        llm: ScriptedLlm([_quizReply(lang)]),
      );
      await _continueLearning(tester, lang);
      await _quizUp(tester, harness, lang);
      await _capture(tester, lang, 'quiz');
      await harness.dispose(tester);
    });

    testWidgets('playground (${lang.code})', (tester) async {
      final python = FakePyRunner();
      addTearDown(python.dispose);
      final harness = await _boot(tester, lang, pyRunner: python);
      await tester.tap(find.text(l.session_mode_playground));
      await pumpUntilFound(tester, find.byType(PlaygroundView));

      // Open the dice program from the student's files…
      final file = '${lang.pick('dobbelsteen', 'dice')}.py';
      await tester.tap(find.text(l.session_playground_open_button));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, file));
      await tester.tap(find.widgetWithText(ListTile, file));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final replace = find.text(l.session_playground_discardDialog_confirm);
      if (replace.evaluate().isNotEmpty) await tester.tap(replace);
      final editor = harness.container.read(
        codeServiceProvider(SessionMode.playground),
      );
      await pumpUntil(
        tester,
        () => editor.getText() == demoPlaygroundCode(lang),
        reason: 'the file never opened',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));

      // …run it…
      await tester.tap(find.text(l.session_runControls_button_run));
      await pumpUntil(tester, () => python.handles.isNotEmpty);
      python.lastHandle
        ..emitStdout(demoPlaygroundOutput(lang))
        ..complete(
          const RunResult(
            status: RunStatus.ok,
            duration: Duration(milliseconds: 57),
          ),
        );
      await pumpUntilFound(
        tester,
        find.descendant(
          of: find.byType(OutputPanel),
          matching: find.textContaining('20', findRichText: true),
        ),
      );

      // …and show the list of files over it.
      await tester.tap(find.text(l.session_playground_open_button));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, file));
      await _capture(tester, lang, 'playground');
      await harness.dispose(tester);
    });

    testWidgets('learning-path (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang);
      await tester.tap(find.byTooltip(l.sidebar_section_map));
      await pumpUntilFound(tester, find.byType(LeerpadPage));
      final current = find.byWidgetPredicate(
        (w) => w is LeerpadChildChip && w.goal.id == kDemoCurrentSubgoal,
      );
      await pumpUntilFound(tester, current);
      // The subgoal the student is on, opened: which of its learning
      // objectives are demonstrated.
      await tester.tap(current);
      await _capture(tester, lang, 'learning-path');
      await harness.dispose(tester);
    });

    testWidgets('trophy-case (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang);
      await tester.tap(find.byTooltip(l.sidebar_section_trophies));
      await pumpUntilFound(tester, find.byType(PrijzenkastPage));
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('badge-tile-effort')),
      );
      // The top: the badges in tiers, bronze, silver and gold.
      await _capture(tester, lang, 'trophy-case');
      // Further down, the class podium: the goals mastered, the medals and
      // the teacher's badge in one view. The page is longer than the window,
      // so this is an image of its own.
      final podium = find.byKey(const ValueKey('badges-section-podium'));
      await tester.scrollUntilVisible(
        podium,
        300,
        scrollable: find
            .descendant(
              of: find.byType(PrijzenkastPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      await Scrollable.ensureVisible(tester.element(podium), alignment: 0.55);
      await _capture(tester, lang, 'trophy-case-podium');
      await harness.dispose(tester);
    });

    testWidgets('level-up (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang);
      await tester.tap(find.byTooltip(l.sidebar_section_map));
      await pumpUntilFound(tester, find.byType(LeerpadPage));
      await _settle(tester);
      // The current subgoal mastered, the way the conductor reports it: its
      // XP lifts the student to the next level.
      harness.container
          .read(levelUpControllerProvider.notifier)
          .armConceptMastered(
            conceptName: 'Beslissingen met if en else',
            goalId: kDemoCurrentSubgoal,
            xpAwarded: kXpPerSubgoal,
          );
      final id = '${demoStudent.oid}_$kDemoCurrentSubgoal';
      harness.cosmos['progress'].upsert({
        ...harness.cosmos['progress'].docs[id]!,
        'progress': 1.0,
      });
      // The overlay is always mounted; the moment is the controller's
      // state, set once the next poll of the progress brings the XP.
      await pumpUntil(
        tester,
        () => harness.container.read(levelUpControllerProvider) != null,
        timeout: const Duration(seconds: 30),
        reason: 'the level was never reached',
      );
      await pumpUntilFound(tester, find.byType(LevelUpOverlay));
      await _capture(tester, lang, 'level-up');
      await harness.dispose(tester);
    });

    // ---- Teacher ------------------------------------------------------------

    testWidgets('students (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_students));
      await pumpUntilFound(tester, find.byType(AccountsPage));
      await pumpUntilFound(tester, find.text(demoStudent.displayName));
      await _capture(tester, lang, 'students');
      await harness.dispose(tester);
    });

    testWidgets('student-detail (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_students));
      await pumpUntilFound(tester, find.byType(AccountsPage));
      await pumpUntilFound(tester, find.text(demoStudent.displayName));
      await tester.tap(find.text(demoStudent.displayName));
      final drawer = find.byType(StudentDetailDrawer);
      await pumpUntilEndDrawerOpen(tester, drawer);
      final chart = find.descendant(
        of: drawer,
        matching: find.byType(LineChart),
      );
      final scrollable = find
          .descendant(of: drawer, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        chart.first,
        200,
        scrollable: scrollable,
        maxScrolls: 100,
      );
      await _capture(tester, lang, 'student-detail');
      await harness.dispose(tester);
    });

    testWidgets('goals (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_goals));
      await pumpUntilFound(tester, find.byType(GoalsPage));
      final root = find.byWidgetPredicate(
        (w) => w is RootRow && w.goal.id == kDemoCurrentRoot,
      );
      await pumpUntilFound(tester, root);
      await tester.tap(root);
      final subgoal = find.byWidgetPredicate(
        (w) => w is ChildRow && w.goal.id == kDemoCurrentSubgoal,
      );
      await pumpUntilFound(tester, subgoal);
      await tester.tap(subgoal);
      await _settle(tester);
      await _pickContentLanguage(tester, lang);
      await _capture(tester, lang, 'goals');
      await harness.dispose(tester);
    });

    testWidgets('lesson-content (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_lessonContent));
      await pumpUntilFound(tester, find.byType(LessonContentPage));
      final row = find.text('Beslissingen met if en else');
      await pumpUntilFound(tester, row);
      await tester.tap(row.first);
      await pumpUntil(
        tester,
        () =>
            harness.lessonRunner.ran.contains(demoLessonCode(DemoLanguage.nl)),
        timeout: const Duration(seconds: 30),
        reason: 'the preview never loaded',
      );
      await _pickContentLanguage(tester, lang);
      if (lang != DemoLanguage.nl) {
        await pumpUntil(
          tester,
          () => harness.lessonRunner.ran.contains(demoLessonCode(lang)),
          timeout: const Duration(seconds: 30),
          reason: 'the translated preview never loaded',
        );
      }
      await _settle(tester, const Duration(seconds: 2));
      await _capture(tester, lang, 'lesson-content');
      await harness.dispose(tester);
    });

    testWidgets('questions (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_questions));
      await pumpUntilFound(tester, find.byType(QuestionsPage));
      final subgoal = find.byKey(
        const Key('questions-subgoal-$kDemoCurrentSubgoal'),
      );
      await pumpUntilFound(tester, subgoal);
      await tester.tap(subgoal);
      await _capture(tester, lang, 'questions');
      await harness.dispose(tester);
    });

    testWidgets('reports (${lang.code})', (tester) async {
      final harness = await _boot(tester, lang, identity: demoTeacher);
      await tester.tap(find.byTooltip(l.sidebar_section_reports));
      await pumpUntilFound(tester, find.byType(ReportsPage));
      final row = find.byKey(Key('reports-row-${demoStudent.oid}'));
      await pumpUntilFound(tester, row);
      // The class the report is for: no teacher, no other class.
      await tester.tap(find.byKey(const Key('reports-class-filter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(kDemoClass).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await pumpUntilFound(tester, row);
      await tester.tap(row);
      await pumpUntilFound(
        tester,
        find.byKey(const Key('reports-detail-justification')),
      );
      await _capture(tester, lang, 'reports');
      await harness.dispose(tester);
    });
  }
}

/// The content-language choice of the page on screen, set to [lang]: the
/// teacher writes the goals and lessons in Dutch, and an English screenshot
/// shows the English translation.
Future<void> _pickContentLanguage(
  WidgetTester tester,
  DemoLanguage lang,
) async {
  if (lang == DemoLanguage.nl) return;
  final picker = find.byType(ContentLanguagePicker);
  if (picker.evaluate().isEmpty) return;
  await tester.tap(
    find.descendant(
      of: picker,
      matching: find.text(_l(lang).settings_language_english),
    ),
  );
  await _settle(tester);
}
