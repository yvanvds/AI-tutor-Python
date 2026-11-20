// #322 — in the editor, `t.` after `t = turtle.Turtle()` opened no
// dropdown, and `t.f` opened one with `for`, `float`, `False`: the words of
// the buffer and Python's keywords, whatever `t` was. These mount the real
// `Editor` (the widget Practice and Playground both render), type into it
// and read the dropdown the package draws: after a dot it lists the
// receiver's members with their parameters, Enter writes the chosen name,
// an unknown receiver opens nothing, and without a dot the editor's own
// words still come.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _turtleCode = 'import turtle\nt = turtle.Turtle()\n';

const _turtleMethods = [
  'backward(distance)',
  'forward(distance)',
  'left(angle)',
  'pencolor(color)',
  'pendown()',
  'penup()',
  'right(angle)',
];

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

CodeController _controller(WidgetTester tester) =>
    tester.widget<CodeField>(find.byType(CodeField)).controller;

/// What the open dropdown lists; empty when none is open.
List<String> _dropdown(WidgetTester tester) {
  final popup = _controller(tester).popupController;
  return popup.shouldShow ? popup.suggestions : const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> mountEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Editor())),
      ),
    );
    await tester.pump();
  }

  /// Unmounts so the controller's debounced analysis timer is cancelled with
  /// the provider scope before the framework's pending-timer check.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// Puts [code] in the buffer with the caret at its end, as opening a file
  /// does, then types [typed] one key at a time after it — the way a student
  /// writes. (A whole buffer swapped for an unrelated one at a collapsed
  /// caret is no keystroke; the package's value handling garbles it.)
  Future<void> type(WidgetTester tester, String code, String typed) async {
    final controller = _controller(tester);
    controller.fullText = code;
    controller.selection = TextSelection.collapsed(offset: code.length);
    await tester.pump();
    for (var k = 1; k <= typed.length; k++) {
      await tester.enterText(_editable, code + typed.substring(0, k));
      await tester.pump();
    }
  }

  testWidgets('after a dot the dropdown lists the methods of a turtle', (
    tester,
  ) async {
    await mountEditor(tester);

    await type(tester, _turtleCode, 't.');
    expect(_dropdown(tester), _turtleMethods);
    expect(find.text('forward(distance)'), findsOneWidget);

    await type(tester, '${_turtleCode}t.', 'f');
    expect(_dropdown(tester), ['forward(distance)']);
    expect(find.text('for'), findsNothing);
    expect(find.text('float'), findsNothing);

    await unmount(tester);
  });

  testWidgets('Enter writes the chosen name after the dot, nothing more', (
    tester,
  ) async {
    await mountEditor(tester);

    await type(tester, _turtleCode, 't.f');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    const written = '${_turtleCode}t.forward';
    expect(_controller(tester).fullText, written);
    expect(_controller(tester).selection.baseOffset, written.length);
    expect(_dropdown(tester), isEmpty);

    // From the full list, arrow down picks the second member.
    const next = '${_turtleCode}t.forward(10)\n';
    await type(tester, next, 't.');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_controller(tester).fullText, '${next}t.forward');

    await unmount(tester);
  });

  testWidgets('a list, a string and a dictionary get their own methods', (
    tester,
  ) async {
    await mountEditor(tester);

    await type(tester, 'getallen = [3, 1, 2]\n', 'getallen.');
    expect(_dropdown(tester), [
      'append(x)',
      'insert(i, x)',
      'pop(i)',
      'remove(x)',
      'sort(reverse=False)',
    ]);

    await type(tester, 'naam = input()\n', 'naam.up');
    expect(_dropdown(tester), ['upper()']);

    await type(tester, 'punten = {}\n', 'punten.k');
    expect(_dropdown(tester), ['keys()']);

    await unmount(tester);
  });

  testWidgets('an unknown receiver opens no dropdown', (tester) async {
    await mountEditor(tester);

    await type(tester, '', 'onbekend.');
    expect(_dropdown(tester), isEmpty);
    await type(tester, 'onbekend.', 'f');
    expect(_dropdown(tester), isEmpty, reason: 'no keywords after a dot');

    await type(tester, 'def teken(t):\n    ', 't.f');
    expect(_dropdown(tester), isEmpty, reason: 't is a parameter: unknown');

    await unmount(tester);
  });

  testWidgets('without a dot the editor still suggests its own words', (
    tester,
  ) async {
    await mountEditor(tester);

    await type(tester, '', 'pri');
    expect(_dropdown(tester), contains('print'));

    await type(tester, 'getallen = [1]\n', 'get');
    expect(_dropdown(tester), contains('getallen'));

    await unmount(tester);
  });
}
