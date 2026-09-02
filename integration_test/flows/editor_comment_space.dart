// End-to-end (#84): a student typing a space inside a `#` comment must see
// the caret move immediately — with the old italic comment token the space
// was inserted but the caret stayed put until the next non-space character,
// which students read as a broken spacebar. The real app renders the real
// playground editor (real page composition, real syntax theme, real fonts)
// and the caret rect must advance for a space typed in a comment exactly as
// it does for one typed in code.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/editor_comment_space.dart -d windows

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// The RenderEditable inside the playground's CodeField — scoped under the
/// CodeField because the page also mounts the chat input's EditableText.
RenderEditable _editorRenderEditable(WidgetTester tester) {
  final root = tester.renderObject(
    find.descendant(
      of: find.byType(CodeField),
      matching: find.byType(EditableText),
    ),
  );
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing a space in a comment moves the caret immediately', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));

    final controller = harness.container
        .read(codeServiceProvider(SessionMode.playground))
        .controller;

    /// Caret x with [text] in the buffer and the caret at [offset] — read
    /// from the same RenderEditable that paints it.
    Future<double> caretDx(String text, int offset) async {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
      await tester.pump();
      return _editorRenderEditable(tester)
          .getLocalRectForCaret(TextPosition(offset: offset))
          .left;
    }

    // The report's case: `# dit is`, then a space, with code below — the
    // space lands just before a newline, inside the comment span.
    final commentBefore = await caretDx('# dit is\nprint(1)\n', 8);
    final commentAfter = await caretDx('# dit is \nprint(1)\n', 9);
    expect(
      commentAfter,
      greaterThan(commentBefore),
      reason: 'a space typed in a comment must move the caret immediately',
    );
    final commentAdvance = commentAfter - commentBefore;

    // Control: the same keystroke in plain code — the behaviour students
    // rightly expect everywhere ("identical to typing a space in code").
    final codeBefore = await caretDx('x = dit\nprint(1)\n', 7);
    final codeAfter = await caretDx('x = dit \nprint(1)\n', 8);
    expect(codeAfter, greaterThan(codeBefore));
    expect(
      commentAdvance,
      moreOrLessEquals(codeAfter - codeBefore, epsilon: 0.5),
      reason: 'the caret must advance in a comment exactly as it does in code',
    );

    await harness.dispose(tester);
  });
}
