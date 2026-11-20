// End-to-end (#322): in the editor, the dropdown after a dot did not list
// the object's functions — `t.` after `t = turtle.Turtle()` opened nothing,
// and `t.f` offered `finally`, `for`, `from`: Python's keywords and the
// words of the buffer, whatever `t` was. Now, in the real app, the dropdown
// after a dot lists the members of the value's type or module from the
// bundled reference (`assets/reference/python_reference.json`, read through
// the real asset bundle here), each with its parameters; Enter writes the
// chosen name; an unknown type opens nothing; and without a dot the editor's
// own words still come.
//
// Only the real app shows that the dropdown can be used where students
// type: it is drawn in the app's overlay at the caret, and the playground
// and the practice page each compose the editor differently (file panel,
// output split, chat beside it). So each page checks the dropdown lies
// inside the window, just below the caret line and within the editor.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/editor_member_dropdown.dart -d windows

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

const _turtleCode = 'import turtle\nt = turtle.Turtle()\n';

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

/// The RenderEditable that paints the code — scoped under the CodeField
/// because the page also mounts the chat input's EditableText.
RenderEditable _editorRenderEditable(WidgetTester tester) {
  final root = tester.renderObject(_editable);
  RenderEditable? found;
  void visit(RenderObject ro) {
    if (found != null) return;
    if (ro is RenderEditable) {
      found = ro;
    } else {
      ro.visitChildren(visit);
    }
  }

  visit(root);
  return found!;
}

/// The caret's rect in window coordinates.
Rect _caretRect(WidgetTester tester, int offset) {
  final editable = _editorRenderEditable(tester);
  final local = editable.getLocalRectForCaret(TextPosition(offset: offset));
  return MatrixUtils.transformRect(editable.getTransformTo(null), local);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('after a dot the dropdown lists the object\'s functions, at '
      'the caret, in the playground and in practice', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);

    final windowSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final window = Offset.zero & windowSize;

    /// Puts [code] in [mode]'s buffer with the caret at its end, then types
    /// [typed] one key at a time after it, as a student does.
    Future<CodeController> type(
      SessionMode mode,
      String code,
      String typed,
    ) async {
      final controller = harness.container
          .read(codeServiceProvider(mode))
          .controller;
      controller.fullText = code;
      controller.selection = TextSelection.collapsed(offset: code.length);
      await tester.pump();
      for (var k = 1; k <= typed.length; k++) {
        await tester.enterText(_editable, code + typed.substring(0, k));
        await tester.pump();
      }
      return controller;
    }

    List<String> dropdown(CodeController controller) =>
        controller.popupController.shouldShow
        ? controller.popupController.suggestions
        : const [];

    /// The dropdown's [entry] lies inside the window, below the caret line
    /// and within the editor.
    void expectAtCaret(String entry, CodeController controller, String where) {
      final item = tester.getRect(find.text(entry));
      final caret = _caretRect(tester, controller.selection.baseOffset);
      final editor = tester.getRect(find.byType(CodeField));
      expect(
        window.contains(item.topLeft) && window.contains(item.bottomRight),
        isTrue,
        reason: '$where: the dropdown entry $item leaves the window $window',
      );
      expect(
        item.top,
        inInclusiveRange(caret.bottom - 1, caret.bottom + 60),
        reason: '$where: the dropdown $item is not just below the caret $caret',
      );
      expect(
        item.left >= editor.left - 1 && item.left < editor.right,
        isTrue,
        reason: '$where: the dropdown $item starts outside the editor $editor',
      );
    }

    // --- Playground ---------------------------------------------------------
    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    await tester.tap(find.byType(CodeField));
    await tester.pump();

    var editor = await type(SessionMode.playground, _turtleCode, 't.');
    // The first dot reads the bundled reference: real asset I/O.
    await pumpUntil(
      tester,
      () => dropdown(editor).isNotEmpty,
      reason: 'no dropdown after `t.`',
    );
    expect(dropdown(editor), [
      'backward(distance)',
      'forward(distance)',
      'left(angle)',
      'pencolor(color)',
      'pendown()',
      'penup()',
      'right(angle)',
    ]);
    await tester.pump();
    expectAtCaret('forward(distance)', editor, 'playground');

    // Typing narrows it; no keyword sneaks in.
    editor = await type(SessionMode.playground, '${_turtleCode}t.', 'f');
    expect(dropdown(editor), ['forward(distance)']);
    expect(find.text('for'), findsNothing);
    expect(find.text('finally'), findsNothing);

    // Enter writes the name — no newline, no space.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editor.fullText, '${_turtleCode}t.forward');
    expect(dropdown(editor), isEmpty);
    expect(find.text('forward(distance)'), findsNothing);

    // A list and a module.
    editor = await type(
      SessionMode.playground,
      'getallen = [3, 1]\n',
      'getallen.',
    );
    expect(dropdown(editor), contains('append(x)'));
    editor = await type(
      SessionMode.playground,
      'import matplotlib.pyplot as plt\n',
      'plt.sh',
    );
    expect(dropdown(editor), ['show()']);

    // Unknown type: nothing at all, rather than something wrong.
    editor = await type(SessionMode.playground, '', 'onbekend.f');
    await tester.pump(const Duration(milliseconds: 200));
    expect(dropdown(editor), isEmpty);

    // Without a dot the editor's own words still come.
    editor = await type(SessionMode.playground, '', 'pri');
    expect(dropdown(editor), contains('print'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    // --- Practice -----------------------------------------------------------
    await tester.tap(find.text('Practice'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    // The playground's editor fades out beside it (the session view's
    // AnimatedSwitcher); wait until only the practice editor is left.
    await pumpUntil(
      tester,
      () => find.byType(CodeField).evaluate().length == 1,
      reason: 'the playground editor never left',
    );
    await tester.tap(find.byType(CodeField));
    await tester.pump();

    editor = await type(SessionMode.practice, _turtleCode, 't.pen');
    expect(dropdown(editor), ['pencolor(color)', 'pendown()', 'penup()']);
    await tester.pump();
    expectAtCaret('penup()', editor, 'practice');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editor.fullText, '${_turtleCode}t.pendown');

    // --- Leaving with the dropdown open -------------------------------------
    // The page fades out while the next fades in, so for a moment both
    // editors are mounted. The fading one keeps its own buffer, and its
    // dropdown closes at the switch — it is drawn in the app's overlay and
    // would not fade — and stays closed: back on the page, Enter is a new
    // line again, not a member from a dropdown no longer on screen.
    editor = await type(SessionMode.practice, _turtleCode, 't.');
    expect(dropdown(editor), isNotEmpty);
    await tester.tap(find.text('Playground'));
    await tester.pump();
    final fading = tester.widgetList<CodeField>(find.byType(CodeField));
    expect(
      fading.map((f) => f.controller).toSet(),
      hasLength(fading.length),
      reason: 'two editors on one buffer during the switch',
    );
    expect(dropdown(editor), isEmpty);
    expect(find.text('forward(distance)'), findsNothing);
    await pumpUntil(
      tester,
      () => find.byType(CodeField).evaluate().length == 1,
      reason: 'the practice editor never left',
    );

    await tester.tap(find.text('Practice'));
    // (PlaygroundView holds a PracticeView too: wait for the editor itself.)
    await pumpUntil(tester, () {
      final fields = find.byType(CodeField).evaluate();
      return fields.length == 1 &&
          (fields.single.widget as CodeField).controller == editor;
    }, reason: 'the practice editor did not come back alone');
    // The keyboard back in the editor without moving the caret.
    await tester.showKeyboard(_editable);
    await tester.pump();
    expect(editor.selection.baseOffset, '${_turtleCode}t.'.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editor.fullText, startsWith('${_turtleCode}t.\n'));

    await harness.dispose(tester);
  });
}
