// #333 — Ctrl+Z in the editor ran on past the start of the exercise into
// the code of the exercise before it, and the one before that. A new
// exercise puts its code in the editor through `CodeService.setText`, which
// replaced the text but kept the package's undo history. Now Ctrl+Z stops at
// the code the exercise opened with — or at the empty editor of an exercise
// that opens empty — and redo still brings back what was typed in it.
//
// #339 — Ctrl+Y, the redo key on Windows, did nothing in the editor: neither
// Flutter nor the package binds it, only Ctrl+Shift+Z. The `Editor` now
// binds Ctrl+Y to the same redo, and Ctrl+Shift+Z keeps working.
//
// The real `Editor` (the package's `CodeField` with its own undo and redo
// bindings). The exercises arrive through `setText`, as the tutor's
// `startNewCode` and a file opened in the Playground do. The end-to-end
// runs, with exercises from the scripted tutor and a file from the
// Playground's browser, are `integration_test/flows/editor_undo_start.dart`.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _exerciseA = 'som = 1 + ___\nprint(som)\n';
const _typedInA = 'klaar = 1';
const _exerciseB = 'naam = ___\nprint(naam)\n';
const _typedInB = 'x = 2';

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// The editor of [mode], focused.
  Future<CodeService> mount(WidgetTester tester, SessionMode mode) async {
    final pc = ProviderContainer(
      overrides: [modeProvider.overrideWith((_) => mode)],
    );
    addTearDown(pc.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: const MaterialApp(home: Scaffold(body: Editor())),
      ),
    );
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    return pc.read(codeServiceProvider(mode));
  }

  /// Types [typed] one key at a time after what is in the editor, as a
  /// student does.
  Future<void> type(WidgetTester tester, CodeService code, String typed) async {
    final before = code.getText();
    for (var k = 1; k <= typed.length; k++) {
      await tester.enterText(_editable, before + typed.substring(0, k));
      await tester.pump();
    }
    expect(code.getText(), before + typed);
  }

  Future<void> ctrlZ(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> ctrlY(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  /// Presses Ctrl+Z [times] times and returns what the editor showed after
  /// each press.
  Future<List<String>> undoMany(
    WidgetTester tester,
    CodeService code, {
    int times = 12,
  }) async {
    final seen = <String>[];
    for (var i = 0; i < times; i++) {
      await ctrlZ(tester);
      seen.add(code.getText());
    }
    return seen;
  }

  /// Lets the history's 5 s typing debounce and the editor's analysis
  /// debounce run out, then unmounts.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('Ctrl+Z stops at the code the exercise opened with; redo '
      'brings back what was typed in it', (tester) async {
    final code = await mount(tester, SessionMode.practice);

    code.setText(_exerciseA);
    await tester.pump();
    await type(tester, code, _typedInA);

    code.setText(_exerciseB);
    await tester.pump();
    await type(tester, code, _typedInB);

    final seen = await undoMany(tester, code);
    expect(code.getText(), _exerciseB);
    for (final text in seen) {
      expect(text, startsWith(_exerciseB), reason: 'undo left exercise B');
      expect(text, isNot(contains('som')), reason: 'exercise A came back');
      expect(text, isNot(contains(CodeService.starterText)));
    }

    // Within the exercise, redo (Ctrl+Shift+Z) gives the typing back.
    await ctrlZ(tester, shift: true);
    expect(code.getText(), _exerciseB + _typedInB);

    await finish(tester);
  });

  testWidgets('an exercise that opens with an empty editor undoes to the '
      'empty editor, not to the exercise before', (tester) async {
    final code = await mount(tester, SessionMode.practice);

    code.setText(_exerciseA);
    await tester.pump();
    await type(tester, code, _typedInA);

    code.setText('');
    await tester.pump();
    await type(tester, code, _typedInB);

    final seen = await undoMany(tester, code);
    expect(code.getText(), isEmpty);
    for (final text in seen) {
      expect(text, isNot(contains('som')), reason: 'exercise A came back');
      expect(text, isNot(contains(_typedInA)));
    }

    await ctrlZ(tester, shift: true);
    expect(code.getText(), _typedInB);

    await finish(tester);
  });

  testWidgets('in the Playground, Ctrl+Z after opening a file stops at the '
      'file', (tester) async {
    final code = await mount(tester, SessionMode.playground);

    await type(tester, code, '\n$_typedInA');

    // What opening a file does with its content.
    code.setText(_exerciseB);
    await tester.pump();
    await type(tester, code, _typedInB);

    final seen = await undoMany(tester, code);
    expect(code.getText(), _exerciseB);
    for (final text in seen) {
      expect(text, startsWith(_exerciseB));
      expect(text, isNot(contains(_typedInA)));
    }

    await finish(tester);
  });

  for (final mode in [SessionMode.practice, SessionMode.playground]) {
    testWidgets('Ctrl+Y brings back what Ctrl+Z undid, as Ctrl+Shift+Z '
        'does (${mode.name})', (tester) async {
      final code = await mount(tester, mode);

      code.setText(_exerciseA);
      await tester.pump();
      await type(tester, code, _typedInA);

      await undoMany(tester, code, times: 3);
      expect(code.getText(), _exerciseA);

      await ctrlY(tester);
      expect(code.getText(), _exerciseA + _typedInA);

      // Nothing left to redo: Ctrl+Y again changes nothing.
      await ctrlY(tester);
      expect(code.getText(), _exerciseA + _typedInA);

      // Ctrl+Shift+Z still redoes.
      await ctrlZ(tester);
      expect(code.getText(), _exerciseA);
      await ctrlZ(tester, shift: true);
      expect(code.getText(), _exerciseA + _typedInA);

      await finish(tester);
    });
  }
}
