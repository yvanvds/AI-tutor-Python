// Issue #131 — in the theory view the chat panel takes 460 px of a student
// laptop for a tutor who does not talk about the theory. The student can now
// fold it to a slim edge strip from the chat header, unfold it from the
// strip, and the choice is remembered per device. The fold is a property of
// the theory view: practice always shows the full panel, playground still
// hides it, and the lesson on the left is the only thing that changes size.
//
// Issue #138 — until the student has pressed either button, the theory view
// follows the window: a window narrower than 1200 px starts with the panel
// folded, a wider one open, and a resize across the line re-folds or unfolds
// it. A stored choice wins on any window; a stored "open" stays open on a
// small screen.
//
// This mounts the real `ModeSwitcher` over the real `SessionView` (all three
// mode views plus the chat panel), drives the fold through the real header
// and strip buttons and the mode through the real top-bar pills, sizes the
// window through the test view, and measures the rendered widths. The lesson
// view must survive a fold as the same element: the WebView it hosts must
// not be re-created by a chat-width change (#128). The end-to-end version,
// over the real WebView, lives in `integration_test/flows/chat_collapse.dart`.

import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
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

/// A wide window and a narrow one, either side of [kChatFoldWindowWidth].
const double _window = 1400;
const double _narrow = 1000;

final _panel = find.byKey(const Key('chat-panel'));
final _showChat = find.byTooltip('Show chat');
final _hideChat = find.byTooltip('Hide chat');
final _unreadDot = find.byKey(const Key('chat-unread-dot'));

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

  /// The chat slide and the mode fade are timed animations, and the editor's
  /// cursor blink never settles, so pump a fixed span past both.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void resize(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 900);
  }

  Future<void> mount(WidgetTester tester, {double width = _window}) async {
    resize(tester, width);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  double panelWidth(WidgetTester tester) => tester.getSize(_panel).width;
  double lessonWidth(WidgetTester tester) =>
      tester.getSize(find.byType(ExplainView)).width;

  testWidgets('Hide chat folds the panel to the strip and the lesson takes '
      'the room; Show chat brings it back; the lesson view is never '
      're-created', (tester) async {
    await mount(tester);

    expect(pc.read(modeProvider), SessionMode.explain);
    expect(panelWidth(tester), chatPanelWidth);
    expect(lessonWidth(tester), _window - chatPanelWidth);
    expect(_showChat, findsNothing);
    final lessonBefore = tester.element(find.byType(ExplainView));

    await tester.tap(_hideChat);
    await settle(tester);

    expect(pc.read(chatCollapsedProvider), isTrue);
    expect(panelWidth(tester), chatCollapsedWidth);
    expect(lessonWidth(tester), _window - chatCollapsedWidth);
    expect(_showChat, findsOneWidget);
    expect(
      tester.element(find.byType(ExplainView)),
      same(lessonBefore),
      reason: 'folding the chat must not re-create the lesson view',
    );

    await tester.tap(_showChat);
    await settle(tester);

    expect(pc.read(chatCollapsedProvider), isFalse);
    expect(panelWidth(tester), chatPanelWidth);
    expect(lessonWidth(tester), _window - chatPanelWidth);
    expect(_showChat, findsNothing);
    expect(tester.element(find.byType(ExplainView)), same(lessonBefore));

    await unmount(tester);
  });

  testWidgets('the remembered choice folds the panel from the first frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
    await mount(tester);

    expect(panelWidth(tester), chatCollapsedWidth);
    expect(_showChat, findsOneWidget);

    await unmount(tester);
  });

  testWidgets('practice ignores the fold; playground still hides the panel; '
      'explain re-applies the fold', (tester) async {
    SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
    await mount(tester);
    expect(panelWidth(tester), chatCollapsedWidth);

    await tester.tap(find.text('Practice'));
    await settle(tester);
    expect(pc.read(chatCollapsedProvider), isTrue, reason: 'still remembered');
    expect(panelWidth(tester), chatPanelWidth);
    expect(_showChat, findsNothing);

    await tester.tap(find.text('Playground'));
    await settle(tester);
    expect(panelWidth(tester), 0);
    expect(_showChat, findsNothing);

    await tester.tap(find.text('Explain'));
    await settle(tester);
    expect(panelWidth(tester), chatCollapsedWidth);
    expect(_showChat, findsOneWidget);

    await unmount(tester);
  });

  testWidgets('with no choice stored, a narrow window starts with the panel '
      'folded from the first frame, the lesson has the room, and nothing is '
      'stored', (tester) async {
    resize(tester, _narrow);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    // The first frame, before the store has answered.
    expect(panelWidth(tester), chatCollapsedWidth);
    final lessonFirst = tester.element(find.byType(ExplainView));

    await settle(tester);
    expect(panelWidth(tester), chatCollapsedWidth);
    expect(lessonWidth(tester), _narrow - chatCollapsedWidth);
    expect(_showChat, findsOneWidget);
    expect(
      tester.element(find.byType(ExplainView)),
      same(lessonFirst),
      reason: 'the window default must not re-create the lesson view',
    );
    expect(pc.read(chatCollapsedProvider), isNull, reason: 'no choice made');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kChatCollapsedPrefsKey), isFalse);

    await unmount(tester);
  });

  testWidgets('a stored "open" keeps the full panel on a narrow window', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: false});
    await mount(tester, width: _narrow);

    expect(panelWidth(tester), chatPanelWidth);
    expect(lessonWidth(tester), _narrow - chatPanelWidth);
    expect(_hideChat, findsOneWidget);
    expect(_showChat, findsNothing);

    await unmount(tester);
  });

  testWidgets('until the student chooses, the panel follows a resize across '
      '1200 px; a choice ends that on any window', (tester) async {
    await mount(tester);
    expect(panelWidth(tester), chatPanelWidth);
    final lessonBefore = tester.element(find.byType(ExplainView));

    resize(tester, _narrow);
    await settle(tester);
    expect(panelWidth(tester), chatCollapsedWidth);
    expect(lessonWidth(tester), _narrow - chatCollapsedWidth);
    expect(_showChat, findsOneWidget);
    expect(tester.element(find.byType(ExplainView)), same(lessonBefore));

    resize(tester, _window);
    await settle(tester);
    expect(panelWidth(tester), chatPanelWidth);
    expect(_showChat, findsNothing);
    expect(pc.read(chatCollapsedProvider), isNull, reason: 'still no choice');

    // Show chat on the narrow window: open is now the decision.
    resize(tester, _narrow);
    await settle(tester);
    expect(panelWidth(tester), chatCollapsedWidth);
    await tester.tap(_showChat);
    await settle(tester);
    expect(panelWidth(tester), chatPanelWidth);
    expect(pc.read(chatCollapsedProvider), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kChatCollapsedPrefsKey), isFalse);

    resize(tester, _window);
    await settle(tester);
    resize(tester, _narrow);
    await settle(tester);
    expect(
      panelWidth(tester),
      chatPanelWidth,
      reason: 'a stored open choice is open on a narrow window too',
    );

    // And a fold is a fold on a wide window.
    await tester.tap(_hideChat);
    await settle(tester);
    resize(tester, _window);
    await settle(tester);
    expect(panelWidth(tester), chatCollapsedWidth);
    expect(prefs.getBool(kChatCollapsedPrefsKey), isTrue);

    await unmount(tester);
  });

  testWidgets('a tutor message behind the strip shows the dot; Show chat '
      'clears it', (tester) async {
    SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
    await mount(tester);
    expect(_unreadDot, findsNothing);

    chat.addTutorMessage('Have a look at the second paragraph.');
    await tester.pump();
    expect(_unreadDot, findsOneWidget);

    await tester.tap(_showChat);
    await settle(tester);
    expect(_unreadDot, findsNothing);
    expect(panelWidth(tester), chatPanelWidth);

    // Fold again: the dot does not come back for a message already seen.
    await tester.tap(_hideChat);
    await settle(tester);
    expect(_unreadDot, findsNothing);

    await unmount(tester);
  });
}
