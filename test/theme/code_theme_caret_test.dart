// Issue #84 — typing a space inside a `#` comment did not move the caret
// until the next non-space character was typed. The space *was* inserted,
// so students read it as a broken spacebar and pressed it again.
//
// Root cause: the `comment` token carried `fontStyle: FontStyle.italic`,
// and Flutter does not advance the caret for a trailing space at the end
// of an italic span when a newline follows (reproduced both with the real
// JetBrains Mono Italic font and with synthesized italic on the regular
// family). The fix keeps every syntax token upright.
//
// These tests mount the same CodeField + theme the Editor uses and measure
// the caret rect exactly where RenderEditable paints it. The comment case
// fails with the italic token and passes without it.

import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/languages/python.dart';

/// The RenderEditable inside the mounted CodeField — the object that lays
/// out the caret the student sees.
RenderEditable _findRenderEditable(WidgetTester tester) {
  final root = tester.renderObject(find.byType(EditableText));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  /// Mounts the editor the way `Editor` does: a python `CodeController`
  /// under the app's syntax theme and mono text style.
  Future<CodeController> mountEditor(WidgetTester tester) async {
    final controller = CodeController(text: '', language: python);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeTheme(
            data: CodeThemeData(styles: tutorCodeTheme),
            child: CodeField(
              controller: controller,
              textStyle: AppMono.code(),
              expands: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  /// Caret x after putting [text] in the buffer with the caret at [offset].
  Future<double> caretDx(
    WidgetTester tester,
    CodeController controller,
    String text,
    int offset,
  ) async {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    await tester.pump();
    return _findRenderEditable(tester)
        .getLocalRectForCaret(TextPosition(offset: offset))
        .left;
  }

  /// Unmounts and disposes so the controller's debounced analysis timer is
  /// cancelled before the framework's pending-timer check.
  Future<void> unmount(WidgetTester tester, CodeController controller) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }

  testWidgets('typing a space in a comment above code moves the caret', (
    tester,
  ) async {
    final controller = await mountEditor(tester);

    // The report's exact case: `# dit is`, then a space, with a line below
    // — so the new space sits just before a newline.
    final before = await caretDx(tester, controller, '# dit is\nprint(1)\n', 8);
    final after = await caretDx(tester, controller, '# dit is \nprint(1)\n', 9);

    await unmount(tester, controller);
    expect(
      after,
      greaterThan(before),
      reason: 'the caret must move as soon as the space is typed',
    );
  });

  testWidgets('typing a space in a comment on the last line moves the caret', (
    tester,
  ) async {
    final controller = await mountEditor(tester);

    final before = await caretDx(tester, controller, '# dit is', 8);
    final after = await caretDx(tester, controller, '# dit is ', 9);

    await unmount(tester, controller);
    expect(after, greaterThan(before));
  });

  testWidgets('typing a space inside a string moves the caret', (tester) async {
    final controller = await mountEditor(tester);

    // Strings are also a distinctly styled span; the caret must behave the
    // same there (acceptance on #84).
    final before = await caretDx(
      tester,
      controller,
      "x = 'dit is'\nprint(1)\n",
      11,
    );
    final after = await caretDx(
      tester,
      controller,
      "x = 'dit is '\nprint(1)\n",
      12,
    );

    await unmount(tester, controller);
    expect(after, greaterThan(before));
  });

  test('no syntax token is italic', () {
    // The caret tests above exercise comments and strings; this pins every
    // token (`quote` included), so the failure mode cannot come back on a
    // token the layout tests do not type into.
    for (final entry in tutorCodeTheme.entries) {
      expect(
        entry.value.fontStyle,
        isNot(FontStyle.italic),
        reason:
            "tutorCodeTheme['${entry.key}'] is italic — a trailing space "
            'typed at the end of that span would not move the caret (#84)',
      );
    }
  });
}
