// End-to-end (#256): the chip next to the streak and the level in the top
// bar shows the level of the exercise on screen.
//
// Before #256 nothing on the student's screen said what level a question was
// asked at; in #253 and #255 only `turn_history` could tell whether a first
// question was hard because it was asked on hard. Now the chip shows the
// level the question's plan set: on a student on `hard` that is `hard`, a
// follow-up is `medium` (CONDUCTOR_POLICY §6.2), and after a notch-drop
// (§2.3) the question is a level lower — the chip says `medium` and its
// tooltip why. Without an exercise on screen — in the lesson before the
// first question, in the Playground, on the learning path — it shows the
// student's calibration, dimmed.
//
// The notch-drop is the strike rule's: the seeded belief has one strong
// negative at calibration on record, and the first answer is the second.
//
// What only a full-app run pins: the real tutor's plan reaching the real top
// bar through the provider — set when the question comes in, `medium` when
// the follow-up does, the lower level when the conductor drops a notch —
// and the real mode switcher and sidebar taking it off screen and back.
// Real app, real navigation, real practice view, editor and chat composer,
// real TutorService → conductor → Cosmos services. Only the model is
// scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/difficulty_chip.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _first = 'naam = ___\nprint("Hallo, " + naam)';
const String _lower = 'print(___)';
const String _followUp = 'Wat doet print() met wat je ertussen zet?';

Map<String, String> _signal(String kind, String strength) => {
  'subgoalId': 's1',
  'loId': 'lo-print',
  'signal': kind,
  'strength': strength,
};

/// The student on `hard`, with a window of ten right answers there: the one
/// wrong answer of this flow demotes nothing (§5.2).
Map<String, dynamic> _hardStudent() {
  final t0 = DateTime.now().toUtc().subtract(const Duration(days: 2));
  return {
    ...accountDoc(studentIdentity),
    'calibration': {
      'difficulty': 'hard',
      'recentAnswers': [
        for (var i = 0; i < 10; i++)
          {
            'quality': 'correct',
            'difficulty': 'hard',
            'at': t0.add(Duration(minutes: i)).toIso8601String(),
          },
      ],
      'recentQuestionTypes': const <String>[],
    },
  };
}

/// One strike on `lo-print` (§2.3): a strong negative at calibration, no
/// positive at calibration ever. One more, and the next question on it is
/// asked a notch lower.
Map<String, dynamic> _oneStrike(DateTime at) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 1.0,
  'beta': 2.0,
  'lastUpdatedAt': at.toIso8601String(),
  'recentNegativesAtCalibrated': 1,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final strip = find.byType(StatStrip);
  final chip = find.descendant(
    of: strip,
    matching: find.byType(DifficultyChip),
  );

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// The chip in the top bar says [word], with the bars of its level in the
  /// accent — or, [dimmed], in the muted colour — and [tooltip] to hover.
  /// Pumps until it does: the level follows the tutor, and the tutor the
  /// model's reply.
  Future<void> expectChip(
    WidgetTester tester, {
    required String word,
    required bool dimmed,
    required String tooltip,
    required String where,
  }) async {
    final text = find.descendant(of: chip, matching: find.text(word));
    await pumpUntil(
      tester,
      () =>
          text.evaluate().isNotEmpty &&
          find.byTooltip(tooltip).evaluate().isNotEmpty,
      reason: '$where: the chip never said "$word" / "$tooltip"',
    );
    expect(chip, findsOneWidget, reason: where);
    final bars = tester.widget<DifficultyBars>(
      find.descendant(of: chip, matching: find.byType(DifficultyBars)),
    );
    expect(
      bars.filled,
      {'easy': 1, 'medium': 2, 'hard': 3}[word],
      reason: '$where: bars',
    );
    expect(
      bars.color,
      dimmed ? AppColors.fgMute : AppColors.accent,
      reason: '$where: ${dimmed ? 'not dimmed' : 'dimmed'}',
    );
    expect(
      tester.widget<Text>(text).style?.color,
      dimmed ? AppColors.fgMute : AppColors.fg,
      reason: '$where: word colour',
    );
    // On screen, inside the strip.
    final s = tester.getRect(strip);
    final c = tester.getRect(chip);
    expect(
      c.left >= s.left - 0.01 && c.right <= s.right + 0.01,
      isTrue,
      reason: '$where: chip $c outside strip $s',
    );
  }

  /// The level of every question the app asked the model for, in order.
  List<String> askedLevels(ScriptedLlm llm) => [
    for (final input in llm.sentInputs)
      if (jsonDecode(input) case {
        'request_type': 'complete_code' || 'write_code',
        'difficulty': final String level,
      })
        level,
  ];

  testWidgets('the top bar shows the level of the exercise on screen: hard '
      'at the calibration, medium for a follow-up, a level lower after a '
      'notch-drop; without an exercise the calibration, dimmed', (
    tester,
  ) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Vul de naam in.', code: _first),
      llmEnvelope(
        text: 'Nog niet: de naam moet tussen aanhalingstekens.',
        meta: jsonEncode({
          'type': 'code_feedback',
          'suggestion': '',
          'overallQuality': 'wrong',
          'loSignals': [_signal('negative', 'strong')],
          'followUp': {'question': _followUp},
        }),
      ),
      llmEnvelope(
        text: 'Bijna: print() toont het op het scherm.',
        meta: jsonEncode({
          'type': 'socratic_feedback',
          'overallQuality': 'partial',
          'loSignals': [_signal('negative', 'weak')],
        }),
      ),
      completeCodeReply(text: 'Een eenvoudiger vraag.', code: _lower),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'accounts': [_hardStudent()],
        'lo_beliefs': [_oneStrike(DateTime.now().toUtc())],
      },
    );
    await harness.boot(tester);

    // The lesson, before the first question: the calibration, dimmed.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await expectChip(
      tester,
      word: 'hard',
      dimmed: true,
      tooltip: 'Your difficulty level: hard',
      where: 'learning path',
    );
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await expectChip(
      tester,
      word: 'hard',
      dimmed: true,
      tooltip: 'Your difficulty level: hard',
      where: 'the lesson',
    );

    // The first question, at the calibration.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == _first,
      timeout: const Duration(seconds: 30),
      reason: 'the first exercise never reached the editor',
    );
    await expectChip(
      tester,
      word: 'hard',
      dimmed: false,
      tooltip: 'This exercise: hard',
      where: 'the first question',
    );

    // Wrong — the second strike — and a follow-up: medium.
    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntilFound(
      tester,
      find.textContaining(_followUp, findRichText: true),
    );
    await expectChip(
      tester,
      word: 'medium',
      dimmed: false,
      tooltip: 'Follow-up question: medium',
      where: 'the follow-up',
    );

    // The follow-up answered, the next question on the LO is a notch lower.
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    final composer = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, composer);
    await tester.tap(composer);
    await tester.pump();
    await tester.enterText(composer, 'Het toont het op het scherm.');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await pumpUntil(
      tester,
      () => editorText(tester) == _lower,
      timeout: const Duration(seconds: 30),
      reason: 'the lower exercise never reached the editor',
    );
    expect(askedLevels(llm), ['hard', 'medium']);
    await expectChip(
      tester,
      word: 'medium',
      dimmed: false,
      tooltip:
          'This exercise: medium, one level lower for this learning objective',
      where: 'the notch-dropped question',
    );
    expect(
      find.descendant(of: strip, matching: find.text('hard')),
      findsNothing,
      reason: 'the level asked, not the calibration',
    );

    // The Playground has no exercise on screen; back in Practice it is.
    final modes = find.byType(ModeSwitcher);
    await tester.tap(
      find.descendant(of: modes, matching: find.text('Playground')),
    );
    await expectChip(
      tester,
      word: 'hard',
      dimmed: true,
      tooltip: 'Your difficulty level: hard',
      where: 'the Playground',
    );
    await tester.tap(
      find.descendant(of: modes, matching: find.text('Practice')),
    );
    await pumpUntilFound(tester, find.byType(PracticeView));
    await expectChip(
      tester,
      word: 'medium',
      dimmed: false,
      tooltip:
          'This exercise: medium, one level lower for this learning objective',
      where: 'back in Practice',
    );
    // The same exercise, once the Playground's editor has faded out.
    await pumpUntil(
      tester,
      () => find.byType(CodeField).evaluate().length == 1,
      reason: "the Playground's editor never left",
    );
    expect(editorText(tester), _lower, reason: 'the same exercise');

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
