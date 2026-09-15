// Issue #122 — a student could not switch to Playground while a quiz (MCQ)
// question was on screen. The mode switch itself always worked; the bug was
// that `PlaygroundView` reuses `PracticeView`, and `PracticeView` swapped its
// editor for `QuizView` whenever `activeMcqProvider` was non-null — in
// *every* mode. So tapping "Playground" flipped the mode and the workspace
// re-rendered the same quiz under a playground header strip, which reads as
// "the switch didn't happen".
//
// This mounts the real `ModeSwitcher` over the real `SessionView` (all three
// mode views plus the chat panel) with an MCQ pending, drives the switch
// through the real top-bar pills, and checks that Playground shows the
// editor while the MCQ stays pending and comes back on return to Practice.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';

import '../../helpers/localization.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() async {}

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _profile = Profile(
  name: 'Sam',
  topic: '',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 0,
  role: Role.student,
);

const _mcq = ActiveMcq(
  prompt: 'What does this print?',
  code: 'print(1 + 1)',
  options: ['2', '11'],
);

void main() {
  late OutputService output;
  late ChatService chat;
  late ProviderContainer pc;

  setUp(() {
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
      localizations: testLocalizations(),
    );
    chat = ChatService();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => _FakeTutorService()),
        outputServiceProvider.overrideWithValue(output),
        chatServiceProvider.overrideWithValue(chat),
        profileProvider.overrideWithValue(_profile),
        modeProvider.overrideWith((_) => SessionMode.practice),
        activeMcqProvider.overrideWith((_) => _mcq),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  Widget buildApp() => UncontrolledProviderScope(
    container: pc,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Column(
          children: [
            ModeSwitcher(),
            Expanded(child: SessionView()),
          ],
        ),
      ),
    ),
  );

  /// The mode swap is an `AnimatedSwitcher` fade; the editor's cursor blink
  /// never settles, so pump a fixed span instead of `pumpAndSettle`.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await settle(tester);
  }

  testWidgets(
    'switching to Playground while an MCQ is pending shows the editor, '
    'and the MCQ is still there on return to Practice',
    (tester) async {
      await mount(tester);

      // Baseline: Practice renders the quiz, not the editor.
      expect(find.byType(QuizView), findsOneWidget);
      expect(find.byType(Editor), findsNothing);

      await tester.tap(find.text('Playground'));
      await settle(tester);

      expect(pc.read(modeProvider), SessionMode.playground);
      expect(find.byType(PlaygroundView), findsOneWidget);
      expect(
        find.byType(QuizView),
        findsNothing,
        reason: 'Playground must not render the pending quiz',
      );
      expect(
        find.byType(Editor),
        findsOneWidget,
        reason: 'Playground must show the code editor',
      );
      // The MCQ is parked, not dropped.
      expect(pc.read(activeMcqProvider), isNotNull);

      await tester.tap(find.text('Practice'));
      await settle(tester);

      expect(pc.read(modeProvider), SessionMode.practice);
      expect(find.byType(QuizView), findsOneWidget);
      expect(find.text(_mcq.prompt), findsOneWidget);
      expect(find.byType(Editor), findsNothing);

      // Unmount before tearDown disposes the container and chat service.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
