// Issue #216 — the question's short ID in the header of the exercise, so the
// teacher can look the question up on the Questions page: next to the pill
// of a quiz, and on the strip above the editor of a code exercise. Small,
// muted, monospace; only while there is a question with an ID, and not in
// the playground, which is no exercise. Next to it a small button copies it
// (#304).
//
// The real `QuizView` and `RunControls`; what the tutor sets
// (`shownQuestionIdProvider`) is seeded. The end-to-end run
// (integration_test/flows/question_id.dart) drives the tutor that sets it.

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/shown_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/widgets/question_id_tag.dart';
import 'package:ai_tutor_python/widgets/submit_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:py_runner/py_runner.dart';

import '../../helpers/localization.dart';
import '../../helpers/test_app_mode.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _id = 's1_3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late ProviderContainer pc;

  ProviderContainer containerFor(AppMode mode) => ProviderContainer(
    overrides: [
      appModeProvider.overrideWithValue(mode),
      tutorServiceProvider.overrideWith(() => _FakeTutorService()),
      outputServiceProvider.overrideWithValue(
        OutputService(
          pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
          localizations: testLocalizations(),
        ),
      ),
    ],
  );

  setUp(() => pc = containerFor(kTestSchoolMode));

  tearDown(() => pc.dispose());

  Future<void> mount(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pump();
  }

  void expectIdTag(WidgetTester tester, Key key) {
    final tag = find.byKey(key);
    expect(tag, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: tag, matching: find.byType(Text)),
    );
    expect(text.data, '#3fa91c');
    // Small and monospace, so `0` and `O` are told apart when read out.
    expect(text.style!.fontFamily, AppMono.code().fontFamily);
    expect(text.style!.fontSize, lessThan(13));
    expect(
      find.descendant(
        of: tag,
        matching: find.byTooltip(
          'The ID of this question. Your teacher can use it to find the '
          'question.',
        ),
      ),
      findsOneWidget,
    );
  }

  /// The copy button of the tag [key] (#304): a click puts the ID on the
  /// clipboard.
  Future<void> expectCopies(WidgetTester tester, Key key) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final button = find.descendant(
      of: find.byKey(key),
      matching: find.byKey(QuestionIdTag.copyKey),
    );
    expect(button, findsOneWidget);
    expect(
      tester.getRect(button).left,
      greaterThanOrEqualTo(tester.getRect(find.text('#3fa91c')).right),
    );

    await tester.tap(button);
    await tester.pump();
    expect(copied, ['#3fa91c']);
    expect(
      find.descendant(of: button, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    await tester.pump(QuestionIdTag.copiedFor);
    expect(tester.takeException(), isNull);
  }

  // #267: no teacher to look the question up in the stand-alone mode.
  testWidgets('stand-alone: the ID is for a bug report, not for a teacher', (
    tester,
  ) async {
    pc.dispose();
    pc = containerFor(const StandaloneMode());
    pc.read(activeMcqProvider.notifier).state = const ActiveMcq(
      prompt: 'Wat drukt dit af?',
      code: 'print(1 + 1)',
      options: ['2', '11'],
    );
    pc.read(shownQuestionIdProvider.notifier).state = _id;
    await mount(tester, const QuizView());

    final tag = find.byKey(const Key('quiz-question-id'));
    expect(
      find.descendant(
        of: tag,
        matching: find.byTooltip(
          'The ID of this question. Mention it when you report a mistake in '
          'the question.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tag,
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains('teacher'),
        ),
      ),
      findsNothing,
    );
  });

  group('a quiz', () {
    setUp(() {
      pc.read(activeMcqProvider.notifier).state = const ActiveMcq(
        prompt: 'Wat drukt dit af?',
        code: 'print(1 + 1)',
        options: ['2', '11'],
      );
    });

    testWidgets('shows the short ID next to its pill', (tester) async {
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(tester, const QuizView());

      expectIdTag(tester, const Key('quiz-question-id'));
      final pill = tester.getCenter(find.text('QUIZ QUESTION'));
      final tag = tester.getCenter(find.byKey(const Key('quiz-question-id')));
      expect(tag.dx, greaterThan(pill.dx), reason: 'next to the pill');
      expect((tag.dy - pill.dy).abs(), lessThan(4), reason: 'on its line');
    });

    testWidgets('a click on the button next to the ID copies it', (
      tester,
    ) async {
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(tester, const QuizView());

      await expectCopies(tester, const Key('quiz-question-id'));
    });

    testWidgets('shows none without an ID', (tester) async {
      await mount(tester, const QuizView());

      expect(find.text('QUIZ QUESTION'), findsOneWidget);
      expect(find.byKey(const Key('quiz-question-id')), findsNothing);
    });
  });

  group('the strip above the editor', () {
    testWidgets('shows the short ID of the code exercise in practice', (
      tester,
    ) async {
      pc.read(modeProvider.notifier).state = SessionMode.practice;
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(tester, const RunControls());

      expectIdTag(tester, const Key('exercise-question-id'));
    });

    testWidgets('a click on the button next to the ID copies it', (
      tester,
    ) async {
      pc.read(modeProvider.notifier).state = SessionMode.practice;
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(tester, const RunControls());

      await expectCopies(tester, const Key('exercise-question-id'));
    });

    testWidgets('in a narrow strip Run drops its shortcut hint, so the ID '
        'and its copy button still fit; the hint is in the tooltip', (
      tester,
    ) async {
      pc.read(modeProvider.notifier).state = SessionMode.practice;
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: RunControls()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('run-shortcut-hint')), findsNothing);
      expect(find.text('Run'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Run'),
          matching: find.byTooltip(submitShortcutLabel()),
        ),
        findsOneWidget,
      );
      final strip = tester.getRect(find.byType(RunControls));
      final copy = find.descendant(
        of: find.byKey(const Key('exercise-question-id')),
        matching: find.byKey(QuestionIdTag.copyKey),
      );
      expect(copy, findsOneWidget);
      expect(tester.getRect(copy).right, lessThanOrEqualTo(strip.right));
      expect(
        tester.getRect(find.text('Run')).right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Reset output')).left),
      );
      // The reference button (#323) fits too: Run gives up its play icon
      // before its word.
      final reference = tester.getRect(find.byTooltip('Reference'));
      expect(reference.left, greaterThanOrEqualTo(tester.getRect(copy).right));
      expect(reference.right, lessThanOrEqualTo(strip.right));
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('with room, Run spells out its shortcut', (tester) async {
      pc.read(modeProvider.notifier).state = SessionMode.practice;
      pc.read(shownQuestionIdProvider.notifier).state = _id;
      await mount(tester, const RunControls());

      expect(find.byKey(const Key('run-shortcut-hint')), findsOneWidget);
    });

    testWidgets('shows none without an ID, nor in the playground', (
      tester,
    ) async {
      pc.read(modeProvider.notifier).state = SessionMode.practice;
      await mount(tester, const RunControls());
      expect(find.byKey(const Key('exercise-question-id')), findsNothing);

      pc.read(shownQuestionIdProvider.notifier).state = _id;
      pc.read(modeProvider.notifier).state = SessionMode.playground;
      await tester.pump();
      expect(find.byKey(const Key('exercise-question-id')), findsNothing);
      expect(find.text('#3fa91c'), findsNothing);
    });
  });
}
