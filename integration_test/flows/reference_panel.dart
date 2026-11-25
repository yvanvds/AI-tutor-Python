// End-to-end (#323): a student who no longer knew how a function was called
// or what it did had to search the whole course. Now the button with the
// book above the editor opens the reference next to the exercise: every
// function and class of the course from the bundled reference
// (`assets/reference/python_reference.json`, read through the real asset
// bundle here), searchable by name or by a word of the explanation, with how
// each is written, one or two sentences, an example, and a link to the lesson
// that explains it, which opens over the exercise and closes back onto it.
//
// What only the real app shows: where the panel lands among the real
// sidebar, editor and chat, in the real font. In Practice it lies over the
// chat, exactly in its place, and the editor keeps its width (#335): in the
// window the runner opens, in the 700 px window of #259 (over the
// half-width chat, the editor keeping its half), and next to the quiz. In
// the Playground, which has no chat, it takes a column of its own beside
// the editor, and a switch back to Practice moves it over the chat. Also:
// that the editor next to it still takes the keyboard; that the lesson
// opens in the real WebView and closing it leaves the student where they
// were; and that the whole panel follows the app language. Any overflow on
// the way fails the flow.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/reference_panel.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/reference/reference_panel.dart';
import 'package:ai_tutor_python/features/reference/reference_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/shown_question.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// The narrow window of #258 and #259.
const double _narrow = 700;

/// The lesson that explains `print`, in Dutch only: in English the link
/// shows its Dutch title, as the theory view does.
const _printLesson = {
  'id': 'uitvoer-print',
  'type': 'content',
  'title': 'Uitvoer met print',
  'body':
      '<h2>Uitvoer met print</h2><p>Met print toon je iets.</p>'
      '<pre><code>print("Hallo")</code></pre>',
  'updatedAt': '2026-05-01T10:00:00Z',
};

/// A quiz the panel opens next to, put up as the tutor would.
const _quiz = ActiveMcq(
  prompt: 'What does this print?',
  code: 'print(len([1, 2]))',
  options: ['2', '3'],
);

final _panel = find.byKey(const Key('reference-panel'));
final _chat = find.byKey(const Key('chat-panel'));
final _search = find.byKey(const Key('reference-search'));
Finder _item(String key) => find.byKey(ValueKey('reference-item-$key'));
Finder _group(String id) => find.byKey(ValueKey('reference-group-$id'));

Rect _window(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

void _resize(WidgetTester tester, double width) {
  tester.view.physicalSize =
      Size(width, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
}

/// Every word and icon of [of] that is on screen lies whole inside [outer]
/// — those a scrolled list clips away are not on screen.
void _partsInside(WidgetTester tester, Finder of, Rect outer, String where) {
  final parts = find.descendant(
    of: of,
    matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
  );
  expect(parts, findsWidgets, reason: where);
  for (final part in parts.evaluate()) {
    final box = part.renderObject! as RenderBox;
    final r = box.localToGlobal(Offset.zero) & box.size;
    expect(_inside(outer, r), isTrue, reason: '$where: ${part.widget} at $r');
  }
}

bool _searchHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _search, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('in Practice the reference lies over the chat and the editor '
      'keeps its width, at 1280 and at 700 px and next to the quiz; it finds '
      'a function by name or by a word, shows its example and opens its '
      'lesson over the exercise; in the Playground it takes a column of its '
      'own; in Dutch it is Dutch', (tester) async {
    final harness = AppHarness(
      extraDocs: {
        'content': [_printLesson],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.text('Practice'));
    await pumpUntilFound(tester, find.byType(RunControls));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_panel, findsNothing);
    final session = tester.getRect(find.byType(SessionView));
    final without = tester.getRect(find.byType(PracticeView));
    expect(without.width, session.width - chatPanelWidth);

    // --- Open over the chat --------------------------------------------------
    // The 1280 px window leaves the session 1208 px: the panel takes the
    // 460 px chat's place and the exercise keeps all of its 748 (#335).
    await tester.tap(
      find.descendant(
        of: find.byType(RunControls),
        matching: find.byTooltip('Reference'),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          _panel.evaluate().isNotEmpty &&
          tester.getRect(_panel) == tester.getRect(_chat),
      reason: 'the panel never settled over the chat',
    );
    await tester.pump(const Duration(milliseconds: 100));
    var exercise = tester.getRect(find.byType(PracticeView));
    expect(tester.getSize(_panel).width, chatPanelWidth);
    expect(exercise, without);
    expect(_inside(_window(tester), tester.getRect(_panel)), isTrue);
    expect(_searchHasFocus(tester), isTrue);
    expect(tester.takeException(), isNull);

    // --- Search by name, and by a word --------------------------------------
    await tester.enterText(_search, 'randint');
    await pumpUntilFound(tester, _item('random.randint'));
    final randint = _item('random.randint');
    expect(
      find.descendant(of: randint, matching: find.text('random.randint(a, b)')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: randint,
        matching: find.textContaining('A random whole number from a to b'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: randint,
        matching: find.textContaining('random.randint(1, 6)'),
      ),
      findsOneWidget,
    );
    _partsInside(tester, randint, tester.getRect(_panel), 'randint');

    await tester.enterText(_search, 'square root');
    await pumpUntilFound(tester, _item('numpy.sqrt'));
    expect(_item('math.sqrt'), findsOneWidget);

    // --- Browse, and the lesson link ----------------------------------------
    await tester.tap(find.byKey(const Key('reference-search-clear')));
    await pumpUntilFound(tester, _group('builtins'));
    await tester.tap(_group('builtins'));
    await pumpUntilFound(tester, _item('builtins.print'));
    final link = find.descendant(
      of: _item('builtins.print'),
      matching: find.text('Lesson: Uitvoer met print'),
    );
    await pumpUntilFound(tester, link);
    // `input` has a lesson too, but not in this app: no link.
    expect(
      find.descendant(
        of: _item('builtins.input'),
        matching: find.textContaining('Lesson:'),
      ),
      findsNothing,
    );
    _partsInside(
      tester,
      _item('builtins.print'),
      tester.getRect(_panel),
      'print',
    );

    await tester.tap(link);
    final lesson = find.byKey(const Key('reference-lesson'));
    await pumpUntilFound(tester, lesson);
    await pumpUntilFound(
      tester,
      find.descendant(
        of: lesson,
        matching: find.descendant(
          of: find.byType(LessonHtmlView),
          matching: find.byType(Texture),
        ),
      ),
      timeout: const Duration(seconds: 30),
    );
    expect(
      find.descendant(of: lesson, matching: find.text('Uitvoer met print')),
      findsOneWidget,
    );
    expect(_inside(_window(tester), tester.getRect(lesson)), isTrue);
    await tester.tap(find.byKey(const Key('reference-lesson-close')));
    await pumpUntilGone(tester, lesson);
    // Back where the student was: the exercise, the panel still open.
    expect(harness.container.read(modeProvider), SessionMode.practice);
    expect(find.byType(PracticeView), findsOneWidget);
    expect(_panel, findsOneWidget);

    // --- The editor next to it still takes the keyboard ---------------------
    final editable = find.descendant(
      of: find.byType(CodeField),
      matching: find.byType(EditableText),
    );
    // The student types over what is there: Ctrl+A, then the new line. The
    // editor is as wide as without the panel, so a tap in its middle lands
    // past the end of the starter line, and flutter_code_editor reads a
    // shorter text put in with the caret there as backspaces; typed over a
    // selection it is the replacement it is.
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final starter = harness.container
        .read(codeServiceProvider(SessionMode.practice))
        .controller;
    expect(
      starter.selection,
      TextSelection(baseOffset: 0, extentOffset: starter.text.length),
      reason: 'Ctrl+A in the editor did not select its code',
    );
    await tester.enterText(editable, 'print("x =", 3)');
    await tester.pump();
    expect(
      harness.container
          .read(codeServiceProvider(SessionMode.practice))
          .getText(),
      'print("x =", 3)',
    );
    expect(_panel, findsOneWidget);

    // --- 700 px: over the chat, the exercise keeps its half -----------------
    _resize(tester, _narrow);
    await pumpUntil(
      tester,
      () => tester.getRect(_panel) == tester.getRect(_chat),
      reason: 'the panel never lay over the chat at $_narrow px',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'at $_narrow px');
    final half = tester.getSize(find.byType(SessionView)).width / 2;
    exercise = tester.getRect(find.byType(PracticeView));
    expect(exercise.width, half);
    expect(_inside(_window(tester), tester.getRect(_panel)), isTrue);
    for (final f in [
      _search,
      find.byKey(const Key('reference-close')),
      _item('builtins.print'),
    ]) {
      expect(
        _inside(tester.getRect(_panel), tester.getRect(f).deflate(0.5)),
        isTrue,
        reason: '$f at $_narrow px',
      );
    }
    // The row above the editor whole, the book button with it — also with
    // the question ID a real exercise shows there (#216), which leaves the
    // least room: Run keeps its word, beside Reset.
    harness.container.read(shownQuestionIdProvider.notifier).state =
        's1_3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e';
    await pumpUntilFound(tester, find.byKey(const Key('exercise-question-id')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'with the question ID');
    final controls = tester.getRect(find.byType(RunControls));
    expect(_inside(exercise, controls), isTrue);
    _partsInside(tester, find.byType(RunControls), controls, 'run controls');
    for (final tip in [
      'Reset output',
      'Reference',
      'Ask for a hint',
      'Send to tutor',
    ]) {
      final button = find.descendant(
        of: find.byType(RunControls),
        matching: find.byTooltip(tip),
      );
      expect(_inside(controls, tester.getRect(button)), isTrue, reason: tip);
    }
    final run = find.descendant(
      of: find.byType(RunControls),
      matching: find.text('Run'),
    );
    expect(run, findsOneWidget);
    expect(
      tester.getRect(run).right,
      lessThanOrEqualTo(tester.getRect(find.byTooltip('Reset output')).left),
    );
    expect(
      tester.getRect(find.byTooltip('Reference')).left,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('exercise-question-id'))).right,
      ),
    );

    // Escape in the panel closes it: the chat is back.
    await tester.tap(_search);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpUntilGone(tester, find.byType(ReferencePanel));
    expect(harness.container.read(referencePanelOpenProvider), isFalse);
    expect(tester.getSize(_chat).width, half);

    // --- The Playground: no chat, a column of its own -----------------------
    _resize(tester, kRunnerWindowSize.width);
    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    await pumpUntil(
      tester,
      () => find.byType(RunControls).evaluate().length == 1,
      reason: 'the practice view never faded out',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(PlaygroundView),
        matching: find.byTooltip('Reference'),
      ),
    );
    final playground = find.byType(PlaygroundView);
    // Its left edge rides the exercise's right edge all the way, so it has
    // settled once its right edge is the window's.
    await pumpUntil(
      tester,
      () =>
          _panel.evaluate().isNotEmpty &&
          tester.getRect(_panel).right == session.right,
      reason: 'the panel never settled beside the Playground editor',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'in the Playground');
    expect(tester.getSize(_panel).width, referencePanelWidth);
    expect(tester.getRect(_panel).left, tester.getRect(playground).right);
    expect(
      tester.getSize(playground).width,
      session.width - referencePanelWidth,
    );
    _partsInside(
      tester,
      find.byType(RunControls),
      tester.getRect(playground),
      'Playground run controls',
    );

    // Back to Practice with the panel open: it moves over the chat, and the
    // exercise has the width it has without it.
    await tester.tap(find.text('Practice'));
    await pumpUntilGone(tester, playground);
    await pumpUntil(
      tester,
      () => tester.getRect(_panel) == tester.getRect(_chat),
      reason: 'the panel never moved over the chat back in Practice',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'back in Practice');
    expect(tester.getRect(find.byType(PracticeView)), without);

    // --- Next to the quiz: over the chat too --------------------------------
    await tester.tap(
      find.descendant(
        of: find.byType(RunControls),
        matching: find.byTooltip('Reference'),
      ),
    );
    await pumpUntilGone(tester, find.byType(ReferencePanel));
    harness.container.read(activeMcqProvider.notifier).state = _quiz;
    await pumpUntilFound(tester, find.byType(QuizView));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(QuizView),
        matching: find.byTooltip('Reference'),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          _panel.evaluate().isNotEmpty &&
          tester.getRect(_panel) == tester.getRect(_chat),
      reason: 'the panel never settled over the chat next to the quiz',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'next to the quiz');
    expect(tester.getRect(find.byType(PracticeView)), without);
    expect(
      tester.getRect(find.byType(QuizView)).right,
      lessThanOrEqualTo(tester.getRect(_panel).left),
      reason: 'the panel lies over the quiz',
    );
    await tester.tap(find.byKey(const Key('reference-close')));
    await pumpUntilGone(tester, find.byType(ReferencePanel));
    harness.container.read(activeMcqProvider.notifier).state = null;
    await pumpUntilFound(tester, find.byType(RunControls));

    // --- In Dutch ------------------------------------------------------------
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Sessie'));
    await pumpUntilFound(tester, find.byType(RunControls));
    await tester.tap(
      find.descendant(
        of: find.byType(RunControls),
        matching: find.byTooltip('Naslag'),
      ),
    );
    await pumpUntilFound(tester, find.byType(ReferencePanel));
    await pumpUntil(
      tester,
      () => _searchHasFocus(tester),
      reason: 'the search field never took the keyboard',
    );
    expect(
      find.descendant(of: _panel, matching: find.text('Naslag')),
      findsOneWidget,
    );
    await tester.enterText(_search, 'wortel');
    await pumpUntilFound(tester, _item('math.sqrt'));
    expect(find.text('De vierkantswortel √x.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reference-search-clear')));
    await pumpUntilFound(tester, find.text('Ingebouwde functies'));
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
