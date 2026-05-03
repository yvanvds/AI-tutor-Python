// 3.1 — `ChatWidget` swaps the chat composer based on `TutorService.state`:
// `idle` → default `Composer`; `working` → `ComposerWaitWidget` (typing
// indicator); `hasFollowUp` → `ComposerContinueWidget` (the "Continue"
// button). A frozen "Continue" button is one of the easiest regressions to
// ship and the hardest to notice in dev, so we lock the wiring here.
//
// Setup: `_FakeTutorService` subclasses `TutorService` so its state can be
// driven via `fakeTutor.set(...)` after mount. `chatServiceProvider` is
// overridden with a real `ChatService` (we only need its `controller`).
// `ProviderScope` wraps the widget under test.
//
// We seed the chat with one message in `setUp` so the underlying
// `ChatAnimatedList` doesn't mount its `EmptyChatList` (which schedules a
// `Future.delayed` Timer that survives widget disposal and trips the
// flutter_test "pending Timer" invariant). Each test ends with
// `unmount(tester)` so the widget tree disposes (cancelling animation
// tickers and timers) before the test framework's invariant checks run.

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_continue_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_wait_widget.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTutorService extends TutorService {
  int initializeSessionCalls = 0;

  @override
  TutorState build() => TutorState.idle;

  void set(TutorState s) => state = s;

  @override
  Future<void> initializeSession({bool force = false}) async {
    initializeSessionCalls++;
  }
}

void main() {
  late _FakeTutorService fakeTutor;
  late ChatService chat;

  setUp(() {
    fakeTutor = _FakeTutorService();
    chat = ChatService();
    // Seed one message so EmptyChatList isn't mounted (its 50ms
    // Future.delayed Timer survives widget disposal otherwise).
    chat.addTutorMessage('hi');
  });

  tearDown(() {
    chat.dispose();
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      tutorServiceProvider.overrideWith(() => fakeTutor),
      chatServiceProvider.overrideWithValue(chat),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ChatWidget()),
    ),
  );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('idle state renders the default Composer', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(ComposerWaitWidget), findsNothing);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('working state renders the ComposerWaitWidget', (tester) async {
    await tester.pumpWidget(buildApp());
    fakeTutor.set(TutorState.working);
    await tester.pump();

    expect(find.byType(ComposerWaitWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('hasFollowUp state renders the ComposerContinueWidget',
      (tester) async {
    await tester.pumpWidget(buildApp());
    fakeTutor.set(TutorState.hasFollowUp);
    await tester.pump();

    expect(find.byType(ComposerContinueWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);
    expect(find.byType(ComposerWaitWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('swaps composer when state transitions idle → working → '
      'hasFollowUp → idle', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    expect(find.byType(Composer), findsOneWidget);

    fakeTutor.set(TutorState.working);
    await tester.pump();
    expect(find.byType(ComposerWaitWidget), findsOneWidget);
    expect(find.byType(Composer), findsNothing);

    fakeTutor.set(TutorState.hasFollowUp);
    await tester.pump();
    expect(find.byType(ComposerContinueWidget), findsOneWidget);
    expect(find.byType(ComposerWaitWidget), findsNothing);

    fakeTutor.set(TutorState.idle);
    await tester.pump();
    expect(find.byType(Composer), findsOneWidget);
    expect(find.byType(ComposerContinueWidget), findsNothing);

    await unmount(tester);
  });

  testWidgets('initializeSession is invoked once after mount', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    expect(fakeTutor.initializeSessionCalls, 1);

    await unmount(tester);
  });
}
