// #323 — the reference must be reachable while practising, without leaving
// the exercise: a panel next to the editor. This mounts the real
// `ModeSwitcher` over the real `SessionView` (the three mode views and the
// chat panel), opens the panel from the real button above the editor and in
// the quiz header, and measures where it lands: in a session with room for
// three it takes a column of its own between the exercise and the chat, in
// a narrow one it lies over the chat and the editor keeps its width, in the
// Playground it has the chat's place, and in the theory view it waits. The
// panel's own content is pinned in test/features/reference/; the
// end-to-end version, in the real window, is
// integration_test/flows/reference_panel.dart.

import 'package:ai_tutor_python/features/reference/reference_panel.dart';
import 'package:ai_tutor_python/features/reference/reference_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  code: 'print(len([1, 2]))',
  options: ['2', '3'],
);

/// A session with room for the exercise, the panel and the chat.
const double _wide = 1400;

/// A 700 px window less the 72 px sidebar (#259).
const double _narrow = 628;

final _panel = find.byKey(const Key('reference-panel'));
final _chat = find.byKey(const Key('chat-panel'));
final _button = find.byTooltip('Reference');

void main() {
  late OutputService output;
  late ChatService chat;
  late ProviderContainer pc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
      localizations: testLocalizations(),
    );
    chat = ChatService();
    // One message so the chat list never mounts its EmptyChatList, whose
    // delayed timer outlives the widget tree.
    chat.addTutorMessage('hi');
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => _FakeTutorService()),
        outputServiceProvider.overrideWithValue(output),
        chatServiceProvider.overrideWithValue(chat),
        profileProvider.overrideWithValue(_profile),
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

  /// The slides and the mode fade are timed animations, and the editor's
  /// cursor blink never settles, so pump a fixed span past them.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);

  Future<void> open(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: find.byType(RunControls), matching: _button),
    );
    await settle(tester);
  }

  testWidgets('with room for three, the button above the editor opens the '
      'panel in a column of its own: the exercise gives up the room, the chat '
      'stays whole, and the search field has the keyboard', (tester) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    expect(_panel, findsNothing);
    expect(rect(tester, find.byType(PracticeView)).width, _wide - 460);

    await open(tester);

    expect(pc.read(referencePanelOpenProvider), isTrue);
    final panel = rect(tester, _panel);
    final practice = rect(tester, find.byType(PracticeView));
    final chatRect = rect(tester, _chat);
    expect(panel.width, referencePanelWidth);
    expect(chatRect.width, chatPanelWidth);
    expect(practice.width, _wide - chatPanelWidth - referencePanelWidth);
    expect(panel.left, practice.right);
    expect(panel.right, chatRect.left);
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('reference-search')),
        matching: find.byType(EditableText),
      ),
    );
    expect(search.focusNode.hasFocus, isTrue);

    // The same button shuts it, and the exercise has its room back.
    await open(tester);
    expect(pc.read(referencePanelOpenProvider), isFalse);
    expect(_panel, findsNothing);
    expect(rect(tester, find.byType(PracticeView)).width, _wide - 460);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('in a narrow session it lies over the chat, exactly in its '
      'place, and the exercise keeps its width', (tester) async {
    await mount(tester, width: _narrow);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    final half = _narrow / 2;
    expect(rect(tester, find.byType(PracticeView)).width, half);

    await open(tester);

    expect(rect(tester, find.byType(PracticeView)).width, half);
    expect(rect(tester, _panel), rect(tester, _chat));
    // Over the chat: a tap there reaches the panel, not the chat.
    expect(
      tester
          .hitTestOnBinding(rect(tester, _chat).center)
          .path
          .any((entry) => entry.target == tester.renderObject(_panel)),
      isTrue,
    );

    // Escape in the panel closes it; the chat is back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(pc.read(referencePanelOpenProvider), isFalse);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('a window made narrow with the panel open moves it from its '
      'own column over the chat, without an overflow on the way', (
    tester,
  ) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    await open(tester);
    expect(rect(tester, _panel).right, rect(tester, _chat).left);

    tester.view.physicalSize = const Size(_narrow, 900);
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'frame $frame');
    }
    await settle(tester);
    expect(rect(tester, _panel), rect(tester, _chat));
    expect(rect(tester, find.byType(PracticeView)).width, _narrow / 2);

    await unmount(tester);
  });

  testWidgets('in the Playground, with no chat, it takes a column of its own; '
      'in the theory view it waits and comes back with the exercise', (
    tester,
  ) async {
    await mount(tester, width: _narrow);
    await tester.tap(find.text('Playground'));
    await settle(tester);

    await open(tester);

    final playground = rect(tester, find.byType(PlaygroundView));
    final panel = rect(tester, _panel);
    expect(playground.width, referenceExerciseMinWidth);
    expect(panel.left, playground.right);
    expect(panel.right, _narrow);

    await tester.tap(find.text('Explain'));
    await settle(tester);
    expect(_panel, findsNothing);
    expect(pc.read(referencePanelOpenProvider), isTrue, reason: 'it waits');

    await tester.tap(find.text('Practice'));
    await settle(tester);
    expect(_panel, findsOneWidget);
    expect(rect(tester, _panel), rect(tester, _chat));
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('a quiz has the button in its header', (tester) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    pc.read(activeMcqProvider.notifier).state = _mcq;
    await settle(tester);
    expect(find.byType(QuizView), findsOneWidget);
    expect(find.byType(RunControls), findsNothing);

    await tester.tap(
      find.descendant(of: find.byType(QuizView), matching: _button),
    );
    await settle(tester);

    expect(pc.read(referencePanelOpenProvider), isTrue);
    expect(find.byType(ReferencePanel), findsOneWidget);
    expect(
      rect(tester, _panel).left,
      rect(tester, find.byType(PracticeView)).right,
    );
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });
}
