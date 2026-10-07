// #256 — the stat strip's difficulty chip shows the level of the exercise
// on screen: the level its plan set, which after a notch-drop is one below
// the calibration (CONDUCTOR_POLICY §2.3), and `medium` for a follow-up
// (§6). Without an exercise on screen — before the first question, in
// Explain, in the Playground, on another page — it shows the account's
// calibration, dimmed. The tooltip says which it is.
//
// The strip in a wide box, so it spells everything out; the plan comes in
// through the provider the tutor writes. That the tutor writes it is in
// test/services/tutor/tutor_service_question_bank_test.dart; the real app in
// integration_test/flows/difficulty_chip.dart.

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/exercise_difficulty.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

const _student = Profile(
  name: 'Sam',
  topic: 'Basics',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 3,
  role: Role.student,
);

QuestionPlan _plan(QuestionDifficulty difficulty, {bool notchDrop = false}) =>
    QuestionPlan(
      type: ChatRequestType.completeCodeQuestion,
      difficulty: difficulty,
      targetLOs: const [],
      reason: TurnSelectionReason(
        candidateLOs: const [],
        chosenReason: 'test',
        notchDropFired: notchDrop,
        notchDropRules: notchDrop
            ? const [NotchDropRule.strongNegatives]
            : const [],
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        profileProvider.overrideWithValue(_student),
        // A student on hard.
        calibrationDifficultyProvider.overrideWithValue(
          QuestionDifficulty.hard,
        ),
      ],
    );
    addTearDown(container.dispose);
    // In Practice, where an exercise is on screen once one came in.
    container.read(sectionProvider.notifier).state = Section.session;
    container.read(modeProvider.notifier).state = SessionMode.practice;
  });

  Future<void> pumpStrip(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(
          // Room for the richest form, under the test font too.
          const Scaffold(
            body: Center(
              child: SizedBox(width: 1600, child: Row(children: [StatStrip()])),
            ),
          ),
          locale: locale,
        ),
      ),
    );
  }

  void show(ExerciseDifficulty? shown) =>
      container.read(shownQuestionDifficultyProvider.notifier).state = shown;

  final chip = find.byType(DifficultyChip);

  /// The chip's word, its bars and how they are coloured.
  void expectChip(
    WidgetTester tester, {
    required String word,
    required int bars,
    required bool dimmed,
    required String tooltip,
  }) {
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text(word)),
      findsOneWidget,
    );
    final text = tester.widget<Text>(
      find.descendant(of: chip, matching: find.text(word)),
    );
    expect(text.style?.color, dimmed ? AppColors.fgMute : AppColors.fg);
    final shown = tester.widget<DifficultyBars>(
      find.descendant(of: chip, matching: find.byType(DifficultyBars)),
    );
    expect(shown.filled, bars);
    expect(shown.color, dimmed ? AppColors.fgMute : AppColors.accent);
    expect(find.byTooltip(tooltip), findsOneWidget);
  }

  testWidgets('an exercise at the calibration: its level, not dimmed', (
    tester,
  ) async {
    show(ExerciseDifficulty.ofPlan(_plan(QuestionDifficulty.hard)));
    await pumpStrip(tester);
    expectChip(
      tester,
      word: 'hard',
      bars: 3,
      dimmed: false,
      tooltip: 'This exercise: hard',
    );
  });

  testWidgets('after a notch-drop: the level the question was asked at, one '
      'lower, and the tooltip says so', (tester) async {
    show(
      ExerciseDifficulty.ofPlan(
        _plan(QuestionDifficulty.medium, notchDrop: true),
      ),
    );
    await pumpStrip(tester);
    expectChip(
      tester,
      word: 'medium',
      bars: 2,
      dimmed: false,
      tooltip:
          'This exercise: medium, one level lower for this learning objective',
    );
    expect(find.text('hard'), findsNothing, reason: 'not the calibration');

    // In Dutch, with the issue's words.
    await pumpStrip(tester, locale: const Locale('nl'));
    expectChip(
      tester,
      word: 'gemiddeld',
      bars: 2,
      dimmed: false,
      tooltip: 'Deze oefening: gemiddeld, een niveau lager voor dit leerdoel',
    );
  });

  testWidgets('no exercise on screen: the calibration, dimmed — before the '
      'first question, and in Explain, the Playground or on another page '
      'while one is in Practice', (tester) async {
    await pumpStrip(tester);
    expectChip(
      tester,
      word: 'hard',
      bars: 3,
      dimmed: true,
      tooltip: 'Your difficulty level: hard',
    );

    // A notch-dropped question in Practice…
    show(
      ExerciseDifficulty.ofPlan(
        _plan(QuestionDifficulty.medium, notchDrop: true),
      ),
    );
    await tester.pump();
    expect(find.text('medium'), findsOneWidget);

    // …is not on screen in Explain or the Playground, nor on another page.
    for (final mode in [SessionMode.explain, SessionMode.playground]) {
      container.read(modeProvider.notifier).state = mode;
      await tester.pump();
      expectChip(
        tester,
        word: 'hard',
        bars: 3,
        dimmed: true,
        tooltip: 'Your difficulty level: hard',
      );
    }
    container.read(modeProvider.notifier).state = SessionMode.practice;
    container.read(sectionProvider.notifier).state = Section.map;
    await tester.pump();
    expectChip(
      tester,
      word: 'hard',
      bars: 3,
      dimmed: true,
      tooltip: 'Your difficulty level: hard',
    );

    // Back in Practice it is.
    container.read(sectionProvider.notifier).state = Section.session;
    await tester.pump();
    expect(find.text('medium'), findsOneWidget);

    // And in Dutch.
    show(null);
    await pumpStrip(tester, locale: const Locale('nl'));
    expectChip(
      tester,
      word: 'moeilijk',
      bars: 3,
      dimmed: true,
      tooltip: 'Je niveau: moeilijk',
    );
  });

  testWidgets('a follow-up question is medium, whatever the question before '
      'it was', (tester) async {
    show(ExerciseDifficulty.followUp);
    await pumpStrip(tester);
    expectChip(
      tester,
      word: 'medium',
      bars: 2,
      dimmed: false,
      tooltip: 'Follow-up question: medium',
    );
  });

  testWidgets('without its word the chip keeps it in the tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        const Scaffold(
          body: Center(
            child: DifficultyChip(
              difficulty: ExerciseDifficulty(
                QuestionDifficulty.easy,
                DifficultySource.plan,
              ),
              withWord: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('easy'), findsNothing);
    expect(
      tester.widget<DifficultyBars>(find.byType(DifficultyBars)).filled,
      1,
    );
    expect(find.byTooltip('This exercise: easy'), findsOneWidget);
  });
}
