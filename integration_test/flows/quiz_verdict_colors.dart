// End-to-end (#179): the colour of a quiz pick while it is being assessed,
// and once the grade lands. Before the fix the picked option was green while
// the tutor was still grading and turned sand when the grade came in — also
// when it said "correct" — so the confirmation of a right answer read as a
// downgrade. And `correct` and `partial` both landed on sand.
//
// The real app renders the quiz (real navigation, real tutor flow, the
// grading reply through the connector's real envelope parsing). The grading
// request is held open so the flow can look at the pick mid-assessment, then
// released so it can look at the pick and the feedback panel once graded.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/quiz_verdict_colors.dart -d windows

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

const String _prompt = 'Welke voorwaarde is waar als temperatuur 18 is?';
const String _picked = 'temperatuur >= 18';
const String _other = 'temperatuur > 18';
const String _feedback = 'Goed gekozen: temperatuur >= 18 is meteen True.';

/// A [ScriptedLlm] that, once [hold] is set, keeps every request waiting
/// until [release] — the window in which the student sees their pick while
/// the tutor is still grading it.
class _GatedLlm extends ScriptedLlm {
  _GatedLlm(super.replies);

  final Completer<void> _gate = Completer<void>();
  bool hold = false;

  void release() => _gate.complete();

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    Stream<StreamChunk> play() => super.sendRequestStream(
      instructions: instructions,
      input: input,
      inputs: inputs,
    );
    if (!hold) return play();
    return Stream.fromFuture(_gate.future).asyncExpand((_) => play());
  }

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    if (hold) await _gate.future;
    return super.sendRequest(
      instructions: instructions,
      input: input,
      inputs: inputs,
    );
  }
}

/// The option row for [label] — the `AnimatedContainer` that draws its tint.
BoxDecoration _optionDecoration(WidgetTester tester, String label) {
  final row = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return row.decoration! as BoxDecoration;
}

/// The feedback panel — the `Container` around the grading text.
BoxDecoration _feedbackDecoration(WidgetTester tester) {
  final panel = tester.widget<Container>(
    find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is TutorMarkdown && w.text.contains('Goed gekozen'),
          ),
          matching: find.byType(Container),
        )
        .first,
  );
  return panel.decoration! as BoxDecoration;
}

/// The token a tinted box was drawn from: its border colour made opaque.
Color _hue(BoxDecoration d) =>
    (d.border! as Border).top.color.withValues(alpha: 1);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The two verdicts the report is about; each must land on its own colour.
  final cases = <({String quality, Color Function() expected, String name})>[
    (quality: 'correct', expected: () => AppColors.accent, name: 'green'),
    (quality: 'partial', expected: () => AppColors.accent2, name: 'sand'),
  ];

  for (final c in cases) {
    testWidgets('a quiz pick is blue while it is assessed, then '
        '${c.name} when a ${c.quality} grade lands', (tester) async {
      final llm = _GatedLlm([
        llmEnvelope(
          text: _prompt,
          meta: jsonEncode({
            'type': 'multiple_choice',
            'prompt': _prompt,
            'code': 'temperatuur = 18',
            'options': [
              {'option': _picked},
              {'option': _other},
            ],
          }),
        ),
        llmEnvelope(
          text: _feedback,
          meta: jsonEncode({
            'type': 'mcq_feedback',
            'overallQuality': c.quality,
            'loSignals': <Object>[],
          }),
        ),
      ]);
      final harness = AppHarness(llm: llm);
      await harness.boot(tester);

      await tester.tap(find.byTooltip('Learning path'));
      await pumpUntilFound(tester, find.byType(LeerpadPage));
      await tester.tap(find.text('Continue'));
      await pumpUntilFound(tester, find.byType(ExplainView));

      // "Try it yourself" mounts the practice view, whose exercise request
      // plays the scripted multiple_choice turn and opens the quiz render.
      await tester.tap(find.text('Try it yourself'));
      await pumpUntilFound(tester, find.byType(QuizView));
      await pumpUntilFound(tester, find.text(_picked));

      // The pick: its grading request stays open until released.
      llm.hold = true;
      await tester.tap(find.text(_picked));
      await pumpUntil(
        tester,
        () => harness.container.read(activeMcqProvider)?.selected == _picked,
        reason: 'the pick was not registered',
      );
      await tester.pump(AppDurations.hover);

      final pending = _hue(_optionDecoration(tester, _picked));
      expect(
        pending,
        AppColors.accent3,
        reason: 'a pick being assessed carries no verdict colour',
      );
      expect(
        pending,
        isNot(AppColors.accent),
        reason: 'green is what "correct" looks like — not before the grade',
      );
      expect(harness.container.read(activeMcqProvider)?.hasFeedback, isFalse);

      // The grade lands.
      llm.release();
      await pumpUntilFound(
        tester,
        find.textContaining('Goed gekozen', findRichText: true),
      );
      await tester.pump(AppDurations.hover);

      final expected = c.expected();
      expect(
        _hue(_optionDecoration(tester, _picked)),
        expected,
        reason: 'the picked option after a ${c.quality} grade',
      );
      expect(
        _hue(_feedbackDecoration(tester)),
        expected,
        reason: 'the feedback panel after a ${c.quality} grade',
      );
      // The option not picked stays neutral.
      final other = _optionDecoration(tester, _other);
      expect((other.border! as Border).top.color, AppColors.ink2);

      await harness.dispose(tester);
    });
  }
}
