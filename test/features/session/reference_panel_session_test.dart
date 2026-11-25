// #323 — the reference must be reachable while practising, without leaving
// the exercise: a panel next to the editor. This mounts the real
// `ModeSwitcher` over the real `SessionView` (the three mode views and the
// chat panel), opens the panel from the real button above the editor and in
// the quiz header, and measures where it lands. In Practice it lies over the
// chat, exactly in its place, at every window width, and the editor keeps
// its width (#335: a column of its own between the exercise and the chat
// left a student laptop almost no room to write code). In the Playground,
// with no chat, it takes a column of its own beside the editor; in the
// theory view it waits. The panel's own content is pinned in
// test/features/reference/; the end-to-end version, in the real window, is
// integration_test/flows/reference_panel.dart.

import 'dart:math' as math;

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

/// A wide session: before #335 the panel took a column of its own here.
const double _wide = 1400;

/// A 1366 px laptop at 125 % scaling (1093 px) less the 72 px sidebar: the
/// student laptop of #138 and #335.
const double _laptop = 1021;

/// A 700 px window less the 72 px sidebar (#259).
const double _narrow = 628;

final _panel = find.byKey(const Key('reference-panel'));
final _chat = find.byKey(const Key('chat-panel'));
final _room = find.byKey(const Key('reference-room'));
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

  testWidgets('in Practice, even in a wide session, the button above the '
      'editor opens the panel over the chat, exactly in its place: the '
      'exercise keeps its width, and the search field has the keyboard', (
    tester,
  ) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    expect(_panel, findsNothing);
    final without = rect(tester, find.byType(PracticeView));
    expect(without.width, _wide - chatPanelWidth);

    await open(tester);

    expect(pc.read(referencePanelOpenProvider), isTrue);
    expect(rect(tester, _panel), rect(tester, _chat));
    expect(rect(tester, _chat).width, chatPanelWidth);
    expect(rect(tester, find.byType(PracticeView)), without);
    expect(rect(tester, _room).width, 0);
    // Over the chat: a tap there reaches the panel, not the chat.
    expect(
      tester
          .hitTestOnBinding(rect(tester, _chat).center)
          .path
          .any((entry) => entry.target == tester.renderObject(_panel)),
      isTrue,
    );
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('reference-search')),
        matching: find.byType(EditableText),
      ),
    );
    expect(search.focusNode.hasFocus, isTrue);

    // The same button shuts it; the chat is back and the exercise never
    // moved.
    await open(tester);
    expect(pc.read(referencePanelOpenProvider), isFalse);
    expect(_panel, findsNothing);
    expect(rect(tester, find.byType(PracticeView)), without);
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

  testWidgets('a window resized with the panel open in Practice keeps it '
      'over the chat, at the chat\'s width, and the exercise at the width it '
      'has without it, without an overflow on the way', (tester) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    await open(tester);
    expect(rect(tester, _panel), rect(tester, _chat));

    for (final width in [_laptop, _narrow, _wide]) {
      tester.view.physicalSize = Size(width, 900);
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: '$width, frame $frame');
      }
      await settle(tester);
      expect(rect(tester, _panel), rect(tester, _chat), reason: '$width');
      expect(
        rect(tester, find.byType(PracticeView)).width,
        width - chatPanelFullWidth(width),
        reason: '$width',
      );
    }

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

  testWidgets('on a student laptop, switching from the Playground to '
      'Practice with the panel open moves it from its column beside the '
      'editor over the chat: the exercise slides from one width to the other, '
      'without a jump or an overflow on the way, and back', (tester) async {
    await mount(tester, width: _laptop);
    await tester.tap(find.text('Playground'));
    await settle(tester);
    await open(tester);

    final playground = rect(tester, find.byType(PlaygroundView));
    expect(rect(tester, _panel).width, referencePanelWidth);
    expect(playground.width, _laptop - referencePanelWidth);
    expect(rect(tester, _panel).left, playground.right);
    expect(rect(tester, _panel).right, _laptop);

    // The exercise ends where the room beside it begins.
    double exercise() => rect(tester, _room).left;

    Future<void> switchTo(String mode, double from, double to) async {
      await tester.tap(find.text(mode));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: '$mode, frame $frame');
        expect(
          exercise(),
          inInclusiveRange(math.min(from, to), math.max(from, to)),
          reason: '$mode, frame $frame: a jump',
        );
      }
      await settle(tester);
      expect(exercise(), to, reason: mode);
    }

    await switchTo(
      'Practice',
      _laptop - referencePanelWidth,
      _laptop - chatPanelWidth,
    );
    expect(rect(tester, _panel), rect(tester, _chat));
    expect(rect(tester, _room).width, 0);

    await switchTo(
      'Playground',
      _laptop - chatPanelWidth,
      _laptop - referencePanelWidth,
    );
    expect(rect(tester, _panel).left, exercise());
    expect(rect(tester, _panel).right, _laptop);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('a quiz has the button in its header, and the panel lies over '
      'the chat there too: the quiz keeps its width', (tester) async {
    await mount(tester, width: _wide);
    await tester.tap(find.text('Practice'));
    await settle(tester);
    pc.read(activeMcqProvider.notifier).state = _mcq;
    await settle(tester);
    expect(find.byType(QuizView), findsOneWidget);
    expect(find.byType(RunControls), findsNothing);
    final without = rect(tester, find.byType(PracticeView));

    await tester.tap(
      find.descendant(of: find.byType(QuizView), matching: _button),
    );
    await settle(tester);

    expect(pc.read(referencePanelOpenProvider), isTrue);
    expect(find.byType(ReferencePanel), findsOneWidget);
    expect(rect(tester, _panel), rect(tester, _chat));
    expect(rect(tester, find.byType(PracticeView)), without);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  group('referencePlacement (#335)', () {
    test('next to a chat it lies over the chat, exactly as wide, at every '
        'session width — never in a column of its own', () {
      for (final session in [_narrow, _laptop, 1208.0, _wide, 2400.0]) {
        final chat = chatPanelFullWidth(session);
        expect(
          referencePlacement(sessionWidth: session, chatWidth: chat),
          ReferencePlacement(width: chat, beside: false),
          reason: '$session',
        );
      }
    });

    test('with no chat (the Playground) it takes a column of its own beside '
        'the exercise, while the exercise keeps its minimum', () {
      expect(
        referencePlacement(sessionWidth: 1208, chatWidth: 0),
        const ReferencePlacement(width: referencePanelWidth, beside: true),
      );
      expect(
        referencePlacement(sessionWidth: _narrow, chatWidth: 0),
        const ReferencePlacement(
          width: _narrow - referenceExerciseMinWidth,
          beside: true,
        ),
      );
      // Too little room for the column: over the right of the exercise.
      expect(
        referencePlacement(sessionWidth: 600, chatWidth: 0),
        const ReferencePlacement(width: referencePanelWidth, beside: false),
      );
    });

    test('next to a chat narrower than the panel can be, it lies over the '
        'right of the exercise', () {
      expect(
        referencePlacement(sessionWidth: 500, chatWidth: 250),
        const ReferencePlacement(width: referencePanelWidth, beside: false),
      );
      expect(
        referencePlacement(sessionWidth: 200, chatWidth: 100),
        const ReferencePlacement(width: 200, beside: false),
      );
    });
  });
}
