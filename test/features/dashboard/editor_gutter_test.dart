// Issue #145 — from line 10 on, the editor's line-number gutter showed each
// number stacked vertically (`1` over `0`) and the number rows no longer
// lined up with the code lines.
//
// Root cause: `GutterStyle.width` is the width of the WHOLE gutter, and
// flutter_code_editor 0.3.5 spends 42 px of it on things that are not the
// number — a fixed 16 px issue column, a fixed 16 px folding column and the
// 10 px `margin`. `width: 44` therefore left the numbers 2 px, so anything
// wider than one glyph soft-wrapped, one digit per row, and the taller rows
// pushed the numbers below out of line with their code.
//
// These mount the real `Editor` (the widget the practice view and the
// playground both render) with a 120-line program and measure the number
// paragraphs where the framework lays them out: one line box per number,
// one row height for every number, and a column wide enough for the widest
// number in the buffer. They fail at `width: 44` (`10` reports two line
// boxes and double the height) and pass at the fixed width.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The gutter's paragraph for line number [number] — scoped under the
/// `CodeField` so nothing else on screen can match.
RenderParagraph _lineNumber(WidgetTester tester, String number) {
  final finder = find.descendant(
    of: find.byType(CodeField),
    matching: find.text(number),
  );
  expect(
    finder,
    findsOneWidget,
    reason: 'the gutter must show line number $number',
  );
  return tester.renderObject<RenderParagraph>(finder);
}

/// How many line boxes the framework broke [number] into — 1 when it fits on
/// one row, 2 when it wrapped (the #145 symptom).
int _lineBoxes(RenderParagraph paragraph, String number) => paragraph
    .getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: number.length),
    )
    .length;

void main() {
  // google_fonts must reach the bundled JetBrains Mono from the asset bundle
  // (the metrics below are real font metrics) and must not fetch.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  /// Mounts the real `Editor` with a [lines]-line program in its buffer.
  Future<void> mountEditor(WidgetTester tester, {required int lines}) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Editor())),
      ),
    );
    await tester.pump();

    tester.widget<CodeField>(find.byType(CodeField)).controller.fullText =
        List.generate(lines, (i) => 'print($i)').join('\n');
    await tester.pump();
  }

  /// Unmounts so the `CodeController`'s debounced analysis timer is cancelled
  /// with the provider scope before the framework's pending-timer check.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('every line number fits on one row', (tester) async {
    await mountEditor(tester, lines: 120);

    // 1 = the one-digit case that worked, 10/99 = the reported break, 120 =
    // three digits, the size the gutter is dimensioned for.
    final numbers = ['1', '9', '10', '99', '120'];
    final boxes = <String, int>{};
    final heights = <String, double>{};
    for (final n in numbers) {
      final paragraph = _lineNumber(tester, n);
      boxes[n] = _lineBoxes(paragraph, n);
      heights[n] = paragraph.size.height;
    }

    await unmount(tester);

    for (final n in numbers) {
      expect(
        boxes[n],
        1,
        reason: 'line number $n wrapped onto ${boxes[n]} rows',
      );
    }
    // Same row height for every number: a wrapped number is a taller row,
    // which is what slid the numbers out of line with the code.
    for (final n in numbers) {
      expect(
        heights[n],
        heights['1'],
        reason:
            'line number $n is ${heights[n]} px tall against '
            '${heights['1']} px for a one-digit number — its row no longer '
            'matches the code line height',
      );
    }
  });

  testWidgets('the number column is wider than the widest line number', (
    tester,
  ) async {
    await mountEditor(tester, lines: 120);

    final widest = _lineNumber(tester, '120');
    final columnWidth = widest.size.width;
    final textWidth = widest.getMaxIntrinsicWidth(double.infinity);

    await unmount(tester);

    expect(
      columnWidth,
      greaterThanOrEqualTo(textWidth),
      reason:
          'the gutter gives line numbers $columnWidth px but a three-digit '
          'number needs $textWidth px — GutterStyle.width must cover the '
          "package's fixed 42 px of issue column, folding column and margin "
          'on top of the digits',
    );
  });
}
