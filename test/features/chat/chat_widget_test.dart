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
import 'package:ai_tutor_python/features/chat/widgets/composer_chrome.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_continue.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_thinking.dart';
import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `read` on a `BuildContext` — how `flutter_chat_ui` hands the composer
// height around. Shown by name so its `Provider` cannot clash with
// Riverpod's.
import 'package:provider/provider.dart' show ReadContext;

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
  xpNext: 500,
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

  // #132: while a theory page is on screen the field says a question is
  // about that page; anywhere else it is the usual hint.
  group('the composer hint', () {
    String hint(WidgetTester tester) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(ComposerIdle),
            matching: find.byType(TextField),
          ),
        )
        .decoration!
        .hintText!;

    testWidgets('names the page in the theory view with a page on screen, '
        'and nothing else', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatWidget)),
      );
      final view = Object();

      // Explain is the mode the app starts in; no page yet.
      expect(container.read(modeProvider), SessionMode.explain);
      expect(hint(tester), 'Type your question or answer…');

      container.read(viewedContentIdProvider.notifier).show(view, 's1');
      await tester.pump();
      expect(hint(tester), 'Ask a question about this explanation…');

      container.read(modeProvider.notifier).state = SessionMode.practice;
      await tester.pump();
      expect(hint(tester), 'Type your question or answer…');

      container.read(modeProvider.notifier).state = SessionMode.explain;
      await tester.pump();
      expect(hint(tester), 'Ask a question about this explanation…');

      container.read(viewedContentIdProvider.notifier).hide(view);
      await tester.pump();
      expect(hint(tester), 'Type your question or answer…');

      await unmount(tester);
    });

    testWidgets('is translated', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tutorServiceProvider.overrideWith(() => fakeTutor),
            chatServiceProvider.overrideWithValue(chat),
            profileProvider.overrideWithValue(_testProfile),
          ],
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ChatWidget()),
          ),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatWidget)),
      );
      expect(hint(tester), 'Typ je vraag of antwoord…');

      container.read(viewedContentIdProvider.notifier).show(Object(), 's1');
      await tester.pump();
      expect(hint(tester), 'Stel een vraag over deze uitleg…');

      await unmount(tester);
    });
  });

  // #146: `flutter_chat_ui` draws the composer *over* the message list and
  // pads the list by whatever height `ComposerChrome` last reported to
  // `ComposerHeightNotifier`. A report that goes stale while the field wraps
  // onto more rows leaves the bottom of the tutor's question behind the
  // composer.
  group('the composer height reported to the message list', () {
    Finder field() => find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );

    /// What the list pads itself by.
    double reported(WidgetTester tester) => tester
        .element(find.byType(ComposerChrome))
        .read<ComposerHeightNotifier>()
        .height;

    /// What the composer actually takes on screen.
    double rendered(WidgetTester tester) =>
        tester.getSize(find.byType(ComposerChrome)).height;

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field(), text);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('follows the field while it wraps onto more rows and back, '
        'with no rebuild of the composer widget', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // One line. This still rebuilds `ComposerIdle` — the send button
      // lights up on the first character — so even the unfixed code
      // re-measured here, and the starting point is honest.
      await type(tester, 'Ik denk dat');
      final oneLine = rendered(tester);
      expect(reported(tester), oneLine);

      // More text, and now nothing above the `TextField` rebuilds: the
      // field already had text, so `ComposerIdle` does not call `setState`
      // and `ComposerChrome` never sees a new widget. Only its layout
      // changes — the case `didUpdateWidget` cannot catch.
      await type(
        tester,
        'Ik denk dat\nde lus drie keer loopt\nomdat range(3)\n'
        'bij nul begint\nen bij twee stopt',
      );
      final grown = rendered(tester);
      expect(
        grown,
        greaterThan(oneLine),
        reason:
            'the composer has to have actually grown for this to test '
            'anything',
      );
      expect(
        reported(tester),
        grown,
        reason:
            'the list pads itself by the reported height; a stale one '
            'hides the bottom of the tutor question behind the composer',
      );

      // And back down when the student trims the answer — again without a
      // rebuild, since the field still has text.
      await type(tester, 'Ik denk dat\nde lus drie keer loopt');
      final shrunk = rendered(tester);
      expect(shrunk, lessThan(grown));
      expect(
        reported(tester),
        shrunk,
        reason:
            'a height left behind by a shrinking composer pads the list '
            'away from the composer instead',
      );

      await unmount(tester);
    });
  });
}
