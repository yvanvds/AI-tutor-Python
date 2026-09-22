// End-to-end (#145): in the real editor the line-number gutter was 44 px
// wide, of which flutter_code_editor spends 42 px on a fixed issue column, a
// fixed folding column and its margin — so the numbers got 2 px. From line 10
// on, each number wrapped one digit per row (`1` over `0`) and the taller
// rows pushed every number below out of line with its code line.
//
// Only a real run shows the second half of that: it needs the real page
// composition (the playground workspace, its width and its scroll context),
// the real bundled JetBrains Mono at the real size the package forces on the
// gutter, and the real code lines to line the numbers up against. This flow
// types a 120-line program into the real playground editor and checks, for
// the numbers the student sees, that each one sits on a single row and that
// the gutter keeps the same row pitch as the code it labels.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/editor_gutter_alignment.dart -d windows

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// One line of the program typed below — a fixed width so a line's start
/// offset in the buffer is arithmetic.
const String _codeLine = 'print(0)';
const int _lineCount = 120;

/// The RenderEditable that paints the code — scoped under the CodeField
/// because the playground also mounts the chat input's EditableText.
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

/// The gutter's paragraph for line number [number], scoped under the
/// CodeField so nothing else on the page can match.
RenderParagraph _lineNumber(WidgetTester tester, int number) {
  final finder = find.descendant(
    of: find.byType(CodeField),
    matching: find.text('$number'),
  );
  expect(
    finder,
    findsOneWidget,
    reason: 'the gutter must show line number $number exactly once',
  );
  return tester.renderObject<RenderParagraph>(finder);
}

/// How many rows the framework broke line number [number] into: 1 when it
/// fits, 2 when it wrapped (the #145 symptom).
int _rows(RenderParagraph paragraph, int number) => paragraph
    .getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: '$number'.length),
    )
    .length;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('line numbers fit on one row and stay level with the code', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));

    final controller = harness.container
        .read(codeServiceProvider(SessionMode.playground))
        .controller;
    controller.fullText = List.generate(
      _lineCount,
      (i) => _codeLine,
    ).join('\n');
    await tester.pump();

    /// Centre of the gutter row for 1-based [line], in global coordinates.
    double numberCentreY(int line) {
      final paragraph = _lineNumber(tester, line);
      return paragraph.localToGlobal(paragraph.size.center(Offset.zero)).dy;
    }

    /// Centre of the code line for 1-based [line], read from the caret rect
    /// the editor paints at the start of that line.
    double codeCentreY(int line) {
      final editable = _editorRenderEditable(tester);
      final rect = editable.getLocalRectForCaret(
        TextPosition(offset: (line - 1) * (_codeLine.length + 1)),
      );
      return editable.localToGlobal(rect.center).dy;
    }

    // Every number the student can read at the top of a fresh buffer, plus
    // the three-digit end of the program: none of them may wrap.
    for (final line in [1, 9, 10, 11, 99, 100, _lineCount]) {
      final paragraph = _lineNumber(tester, line);
      expect(
        _rows(paragraph, line),
        1,
        reason:
            'line number $line wrapped onto ${_rows(paragraph, line)} rows in '
            'the real editor — the gutter is too narrow for its digits',
      );
    }

    // Alignment: the gutter row for line 10 must sit as far below the row for
    // line 1 as line 10's code sits below line 1's. With the wrapped numbers
    // the gutter rows were ~2x the code pitch, so the numbers drifted further
    // out of line with every line. A whole line is ~22 px, so 2 px of slack
    // is far tighter than the failure and safe against rounding.
    final gutterPitch = numberCentreY(10) - numberCentreY(1);
    final codePitch = codeCentreY(10) - codeCentreY(1);
    expect(
      gutterPitch,
      closeTo(codePitch, 2),
      reason:
          'the gutter advances $gutterPitch px over 9 lines while the code '
          'advances $codePitch px — the numbers no longer line up with the '
          'lines they label',
    );

    /// How far line [line]'s number sits from its own code line. A number and
    /// its code are measured from different boxes — a table cell against the
    /// caret rect — so a small fixed gap is normal; what matters is that the
    /// gap is the *same* on every line. Wrapped numbers made it grow.
    double gap(int line) => numberCentreY(line) - codeCentreY(line);

    final firstGap = gap(1);
    final lineHeight = codePitch / 9;
    expect(
      firstGap.abs(),
      lessThan(lineHeight / 2),
      reason:
          'line number 1 is ${firstGap.abs()} px off its code line, more than '
          'half of a ${lineHeight}px line — it reads as belonging to another '
          'line',
    );
    for (final line in [10, 100, _lineCount]) {
      expect(
        gap(line),
        closeTo(firstGap, 1),
        reason:
            'line number $line sits ${gap(line)} px from its code line while '
            'line 1 sits $firstGap px from its own — the gutter has drifted '
            'out of line with the code',
      );
    }

    await harness.dispose(tester);
  });
}
