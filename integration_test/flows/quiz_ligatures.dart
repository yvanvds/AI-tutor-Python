// End-to-end (#83): a quiz turn whose code block and answer options are full
// of Python comparison operators. JetBrains Mono ships programming ligatures
// on by default (`calt`), which fused `==` / `!=` / `>=` into ═ ≠ ≥ — glyphs
// a beginner can neither type nor look up, on exactly the quiz that teaches
// the difference between `=` and `==`. The real app renders the quiz (real
// navigation, real `HighlightView` + syntax theme, real option rows) and
// every span of code text must carry the ligature disables.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/quiz_ligatures.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// The reproduction from #83: comparisons that ligate when `calt` is on.
const String kQuizCode = 'print(x == 5)\nprint(x != 4)\nprint(x >= 6)';

/// Option text with an operator — the "omdat ═ en ≠ ..." half of the bug.
const String kOptionA = 'omdat == twee waarden vergelijkt';
const String kOptionB = 'omdat != en == niet samen gebruikt mogen worden';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppHarness harness;

  setUp(() {
    harness = AppHarness(
      llm: ScriptedLlm([
        llmEnvelope(
          text: 'Hier komt een quizvraag.',
          meta: jsonEncode({
            'type': 'multiple_choice',
            'prompt': 'Wat is waar over deze code?',
            'code': kQuizCode,
            'options': [
              {'option': kOptionA},
              {'option': kOptionB},
            ],
          }),
        ),
      ]),
    );
  });

  /// True when [style] explicitly disables both ligature features.
  bool stripsLigatures(TextStyle? style) {
    final features = style?.fontFeatures;
    if (features == null) return false;
    bool disables(String tag) =>
        features.any((f) => f.feature == tag && f.value == 0);
    return disables('calt') && disables('liga');
  }

  testWidgets('quiz code block and answer options render == / != / >= '
      'without JetBrains Mono ligatures', (tester) async {
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // "Try it yourself" mounts the practice view, whose exercise request
    // plays the scripted multiple_choice turn and opens the quiz render.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));

    // The code card: the highlighted span tree the student actually reads.
    final richText = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(HighlightView),
            matching: find.byType(RichText),
          )
          .first,
    );

    // The characters themselves are the literal two-character operators...
    expect(richText.text.toPlainText(), contains('x == 5'));
    expect(richText.text.toPlainText(), contains('x != 4'));
    expect(richText.text.toPlainText(), contains('x >= 6'));

    // ...and no span in the tree may shape them into ligatures: the root
    // style and every styled token span must disable `calt`/`liga`.
    expect(
      stripsLigatures(richText.text.style),
      isTrue,
      reason: 'the code card base style would render == as ═',
    );
    // Manual walk: `visitChildren` skips the styled wrapper spans (they
    // carry children, not text), which is exactly where the token styles
    // live.
    var styledSpans = 0;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      final style = span.style;
      if (style != null) {
        styledSpans++;
        expect(
          stripsLigatures(style),
          isTrue,
          reason: 'a syntax token span would render == as ═',
        );
      }
      span.children?.forEach(walk);
    }

    (richText.text as TextSpan).children?.forEach(walk);
    expect(
      styledSpans,
      greaterThan(0),
      reason: 'no styled syntax token spans found — wrong RichText?',
    );

    // The answer options ("omdat ═ en ≠ ..." in the bug report). Shuffled
    // by the handler, so find them by text.
    for (final option in [kOptionA, kOptionB]) {
      final text = tester.widget<Text>(find.text(option));
      expect(
        stripsLigatures(text.style),
        isTrue,
        reason: 'option "$option" would render its operators as ligatures',
      );
    }

    await harness.dispose(tester);
  });
}
