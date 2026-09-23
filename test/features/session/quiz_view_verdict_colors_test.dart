// Issue #179 — in a quiz (MCQ) the picked option was tinted green while the
// grade was being assessed, then turned sand the moment the grade came in,
// even when it said "correct". Green-then-sand reads as a downgrade at the
// very moment the answer is confirmed right. And `correct` and `partial`
// landed on the same sand tint, so "partly right" looked like "right".
//
// The mapping now, for the picked option and the feedback panel alike:
// being assessed → accent3 (blue, no verdict), correct → accent (green),
// partial → accent2 (sand), wrong → danger (red).
//
// This mounts the real `QuizView` with an MCQ in each state and reads the
// tint off the option row and the feedback panel.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _picked = 'temperatuur >= 18';
const _other = 'temperatuur > 18';
const _feedback = 'Goed gekozen: `temperatuur >= 18` is meteen True.';

const _question = ActiveMcq(
  prompt: 'Welke voorwaarde is waar bij 18 graden?',
  code: 'temperatuur = 18',
  options: [_picked, _other],
);

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

/// The feedback panel under the options — the `Container` around the
/// feedback text.
BoxDecoration _feedbackDecoration(WidgetTester tester) {
  final panel = tester.widget<Container>(
    find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is TutorMarkdown && w.text == _feedback,
          ),
          matching: find.byType(Container),
        )
        .first,
  );
  return panel.decoration! as BoxDecoration;
}

/// The full-strength hue a tinted box is drawn in: its border colour with
/// the alpha taken back to opaque, which is exactly the token it was made
/// from (every token is opaque).
Color _hue(BoxDecoration d) =>
    (d.border! as Border).top.color.withValues(alpha: 1);

void main() {
  late ProviderContainer pc;

  setUp(() {
    pc = ProviderContainer(
      overrides: [tutorServiceProvider.overrideWith(() => _FakeTutorService())],
    );
  });

  tearDown(() => pc.dispose());

  Future<void> mount(WidgetTester tester, ActiveMcq mcq) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pc.read(activeMcqProvider.notifier).state = mcq;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: QuizView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ActiveMcq graded(AnswerQuality quality) => _question.copyWith(
    selected: _picked,
    feedback: _feedback,
    feedbackQuality: quality,
  );

  testWidgets('a pick being assessed is blue, not green', (tester) async {
    await mount(tester, _question.copyWith(selected: _picked));

    final hue = _hue(_optionDecoration(tester, _picked));
    expect(hue, AppColors.accent3);
    expect(
      hue,
      isNot(AppColors.accent),
      reason: 'green is what "correct" looks like — not before the grade',
    );
    expect(find.byType(TutorMarkdown), findsOneWidget); // no feedback yet
  });

  testWidgets('a correct pick and its feedback are green', (tester) async {
    await mount(tester, graded(AnswerQuality.correct));

    expect(_hue(_optionDecoration(tester, _picked)), AppColors.accent);
    expect(_hue(_feedbackDecoration(tester)), AppColors.accent);
  });

  testWidgets('a partly right pick and its feedback are sand, unlike correct', (
    tester,
  ) async {
    await mount(tester, graded(AnswerQuality.partial));

    final option = _hue(_optionDecoration(tester, _picked));
    final panel = _hue(_feedbackDecoration(tester));
    expect(option, AppColors.accent2);
    expect(panel, AppColors.accent2);
    expect(
      option,
      isNot(AppColors.accent),
      reason: 'partly right must not look the same as right',
    );
  });

  testWidgets('a wrong pick and its feedback are red', (tester) async {
    await mount(tester, graded(AnswerQuality.wrong));

    expect(_hue(_optionDecoration(tester, _picked)), AppColors.danger);
    expect(_hue(_feedbackDecoration(tester)), AppColors.danger);
  });

  testWidgets('the options not picked stay neutral whatever the verdict', (
    tester,
  ) async {
    await mount(tester, graded(AnswerQuality.correct));

    final other = _optionDecoration(tester, _other);
    expect(other.color, AppColors.ink1);
    expect((other.border! as Border).top.color, AppColors.ink2);
  });

  testWidgets(
    'the pick goes from blue to green when a correct grade lands — the '
    'reported sequence',
    (tester) async {
      await mount(tester, _question.copyWith(selected: _picked));
      expect(_hue(_optionDecoration(tester, _picked)), AppColors.accent3);

      pc.read(activeMcqProvider.notifier).state = graded(AnswerQuality.correct);
      await tester.pumpAndSettle();

      expect(_hue(_optionDecoration(tester, _picked)), AppColors.accent);
      expect(_hue(_feedbackDecoration(tester)), AppColors.accent);
    },
  );
}
