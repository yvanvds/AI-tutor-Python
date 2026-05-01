// 3.1 — `ChatWidget` swaps the chat composer based on `TutorService.state`:
// `idle` → default `Composer`; `working` → `ComposerWaitWidget` (typing
// indicator); `hasFollowUp` → `ComposerContinueWidget` (the "Continue"
// button). A frozen "Continue" button is one of the easiest regressions to
// ship and the hardest to notice in dev, so we lock the wiring here.
//
// Setup: register a `MockTutorService` at the locator that exposes a real
// `ValueNotifier<TutorState>` (so the widget's `ValueListenableBuilder`
// rebuilds on `state.value = ...`), and a real `ChatService` (we only need
// its `controller` and don't assert on chat behaviour). `initializeSession`
// runs in a `Future.microtask` after mount, so we stub it to a no-op.
//
// We seed the chat with one message in `setUp` so the underlying
// `ChatAnimatedList` doesn't mount its `EmptyChatList` (which schedules a
// `Future.delayed` Timer that survives widget disposal and trips the
// flutter_test "pending Timer" invariant). Each test ends with
// `_unmount(tester)` so the widget tree disposes (cancelling animation
// tickers and timers) before the test framework's invariant checks run.

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_continue_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_wait_widget.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

void main() {
  late MockTutorService tutor;
  late ChatService chat;
  late ValueNotifier<TutorState> stateNotifier;

  setUp(() {
    tutor = MockTutorService();
    chat = ChatService();
    stateNotifier = ValueNotifier<TutorState>(TutorState.idle);

    // Seed one message so EmptyChatList isn't mounted (its 50ms
    // Future.delayed Timer survives widget disposal otherwise).
    chat.addTutorMessage('hi');

    when(() => tutor.state).thenReturn(stateNotifier);
    when(() => tutor.initializeSession(force: any<bool>(named: 'force')))
        .thenAnswer((_) async {});

    registerMock<TutorService>(tutor);
    registerMock<ChatService>(chat);
  });

  tearDown(() async {
    stateNotifier.dispose();
    chat.dispose();
    await resetLocator();
  });

  Future<void> pumpChatWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatWidget(),
        ),
      ),
    );
    // Two frames: first mounts Chat, second lets the composer builder
    // produce its widget. Avoid pumpAndSettle — the wait composer uses
    // `LoadingAnimationWidget` which animates forever.
    await tester.pump();
  }

  // Replace the widget tree with an empty container so all State.dispose
  // hooks fire (cancelling animation tickers from LoadingAnimationWidget
  // and any pending timers in ChatAnimatedList) before the test framework
  // checks the pending-Timer invariant.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('idle state renders the default Composer', (tester) async {
    stateNotifier.value = TutorState.idle;
    await pumpChatWidget(tester);

    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(ComposerWaitWidget), findsNothing);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('working state renders the ComposerWaitWidget', (tester) async {
    stateNotifier.value = TutorState.working;
    await pumpChatWidget(tester);

    expect(find.byType(ComposerWaitWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('hasFollowUp state renders the ComposerContinueWidget',
      (tester) async {
    stateNotifier.value = TutorState.hasFollowUp;
    await pumpChatWidget(tester);

    expect(find.byType(ComposerContinueWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);
    expect(find.byType(ComposerWaitWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('swaps composer when state transitions idle → working → '
      'hasFollowUp → idle', (tester) async {
    await pumpChatWidget(tester);
    expect(find.byType(Composer), findsOneWidget);

    stateNotifier.value = TutorState.working;
    await tester.pump();
    expect(find.byType(ComposerWaitWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);

    stateNotifier.value = TutorState.hasFollowUp;
    await tester.pump();
    expect(find.byType(ComposerContinueWidget), findsOneWidget);
    expect(find.byType(ComposerWaitWidget), findsNothing);

    stateNotifier.value = TutorState.idle;
    await tester.pump();
    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('initializeSession is invoked once after mount', (tester) async {
    await pumpChatWidget(tester);
    // The microtask scheduled in initState fires on the first pump.
    verify(() => tutor.initializeSession()).called(1);

    await unmount(tester);
  });
}
