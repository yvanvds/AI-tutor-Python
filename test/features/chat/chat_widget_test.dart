// 3.1 — `ChatWidget` swaps the chat composer based on `TutorService.state`:
// `idle` → `ComposerIdle`; `working` → `ComposerThinking` (typing indicator);
// `hasFollowUp` → `ComposerContinue` (the "Continue" button). A frozen
// "Continue" button is one of the easiest regressions to ship and the hardest
// to notice in dev, so we lock the wiring here.
//
// Setup: `_FakeTutorService` subclasses `TutorService` so its state can be
// driven via `fakeTutor.set(...)` after mount. `chatServiceProvider` is
// overridden with a real `ChatService` (we only need its `controller`).
// `profileProvider` is overridden with a fixed `Profile` so the new
// `ChatHeader` builds without pulling account/auth services.
// `ProviderScope` wraps the widget under test.
//
// We seed the chat with one message in `setUp` so the underlying
// `ChatAnimatedList` doesn't mount its `EmptyChatList` (which schedules a
// `Future.delayed` Timer that survives widget disposal and trips the
// flutter_test "pending Timer" invariant). Each test ends with
// `unmount(tester)` so the widget tree disposes (cancelling animation
// tickers and timers) before the test framework's invariant checks run.

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_continue.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_thinking.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
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

const _testProfile = Profile(
  name: 'Test',
  topic: '',
  level: 1,
  xp: 0,
  xpNext: 1500,
  streak: 0,
  role: Role.student,
);

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
      profileProvider.overrideWithValue(_testProfile),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ChatWidget()),
    ),
  );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('idle state renders the ComposerIdle', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(ComposerIdle), findsOneWidget);
    expect(find.byType(ComposerThinking), findsNothing);
    expect(find.byType(ComposerContinue), findsNothing);

    await unmount(tester);
  });

  testWidgets('working state renders the ComposerThinking', (tester) async {
    await tester.pumpWidget(buildApp());
    fakeTutor.set(TutorState.working);
    await tester.pump();

    expect(find.byType(ComposerThinking), findsOneWidget);
    expect(find.byType(ComposerIdle), findsNothing);
    expect(find.byType(ComposerContinue), findsNothing);

    await unmount(tester);
  });

  testWidgets('hasFollowUp state renders the ComposerContinue', (tester) async {
    await tester.pumpWidget(buildApp());
    fakeTutor.set(TutorState.hasFollowUp);
    await tester.pump();

    expect(find.byType(ComposerContinue), findsOneWidget);
    expect(find.byType(ComposerIdle), findsNothing);
    expect(find.byType(ComposerThinking), findsNothing);

    await unmount(tester);
  });

  testWidgets('swaps composer when state transitions idle → working → '
      'hasFollowUp → idle', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    expect(find.byType(ComposerIdle), findsOneWidget);

    fakeTutor.set(TutorState.working);
    await tester.pump();
    expect(find.byType(ComposerThinking), findsOneWidget);
    expect(find.byType(ComposerIdle), findsNothing);

    fakeTutor.set(TutorState.hasFollowUp);
    await tester.pump();
    expect(find.byType(ComposerContinue), findsOneWidget);
    expect(find.byType(ComposerThinking), findsNothing);

    fakeTutor.set(TutorState.idle);
    await tester.pump();
    expect(find.byType(ComposerIdle), findsOneWidget);
    expect(find.byType(ComposerContinue), findsNothing);

    await unmount(tester);
  });

  testWidgets('initializeSession is invoked once after mount', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    expect(fakeTutor.initializeSessionCalls, 1);

    await unmount(tester);
  });
}
