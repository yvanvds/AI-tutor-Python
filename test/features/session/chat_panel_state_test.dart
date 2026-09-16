// Issue #131 — the chat panel's collapse in the theory view: the remembered
// choice round-trips through SharedPreferences, the layout derived from it
// applies to `explain` only, and the unread flag follows the tutor-message
// count while the full panel is off screen.
//
// Issue #138 — until the student has chosen, the layout follows the window:
// folded under 1200 px, open above, live across a resize; a stored choice
// wins on any window, and a stored `false` means open on a small screen.

import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mcq = ActiveMcq(prompt: 'q', code: '', options: ['a', 'b']);

/// A wide and a narrow window, either side of [kChatFoldWindowWidth].
const double _wide = 1400;
const double _narrow = 1000;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// The window width the container reports, changeable mid-test the way a
  /// resize would change it.
  final windowWidth = StateProvider<double>((_) => _wide);

  ProviderContainer container({
    SessionMode mode = SessionMode.explain,
    ChatService? chat,
    double width = _wide,
  }) {
    final c = ProviderContainer(
      overrides: [
        modeProvider.overrideWith((_) => mode),
        windowWidth.overrideWith((_) => width),
        windowWidthProvider.overrideWith((ref) => ref.watch(windowWidth)),
        if (chat != null) chatServiceProvider.overrideWithValue(chat),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('chatCollapsedProvider', () {
    test('starts unset: no choice until a button is pressed', () async {
      final c = container();
      expect(c.read(chatCollapsedProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatCollapsedProvider), isNull, reason: 'after hydration');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kChatCollapsedPrefsKey), isFalse);
    });

    test('hydrates a stored false as a choice, not as unset', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: false});
      final c = container();
      c.read(chatCollapsedProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatCollapsedProvider), isFalse);
    });

    test('a button pressed before the store answered wins', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
      final c = container();
      c.read(chatCollapsedProvider);
      final done = c.read(chatCollapsedProvider.notifier).expand();
      expect(c.read(chatCollapsedProvider), isFalse);
      await done;
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatCollapsedProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kChatCollapsedPrefsKey), isFalse);
    });

    test('collapse() applies at once and stores the choice', () async {
      final c = container();
      await c.read(chatCollapsedProvider.notifier).collapse();
      expect(c.read(chatCollapsedProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kChatCollapsedPrefsKey), isTrue);
    });

    test('expand() stores the choice too, as false — not a removal', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
      final c = container();
      await c.read(chatCollapsedProvider.notifier).expand();
      expect(c.read(chatCollapsedProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kChatCollapsedPrefsKey), isFalse);
    });

    test('hydrates a stored true on first read', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
      final c = container();
      c.read(chatCollapsedProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatCollapsedProvider), isTrue);
    });

    test(
      'the flag round-trips: stored by one container, read by the next',
      () async {
        await container().read(chatCollapsedProvider.notifier).collapse();

        final next = container();
        next.read(chatCollapsedProvider);
        await Future<void>.delayed(Duration.zero);
        expect(next.read(chatCollapsedProvider), isTrue);
      },
    );
  });

  group('chatPanelLayoutProvider', () {
    test('explain shows the full panel until the student folds it', () async {
      final c = container();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);

      await c.read(chatCollapsedProvider.notifier).collapse();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

      await c.read(chatCollapsedProvider.notifier).expand();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
    });

    test('with no choice stored, a narrow window starts folded and stores '
        'nothing', () async {
      final c = container(width: _narrow);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
      expect(c.read(chatCollapsedProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kChatCollapsedPrefsKey), isFalse);
    });

    test('the fold line is 1200 px: just under folds, at it opens', () {
      expect(
        container(width: kChatFoldWindowWidth - 1)
            .read(chatPanelLayoutProvider),
        ChatPanelLayout.collapsed,
      );
      expect(
        container(width: kChatFoldWindowWidth).read(chatPanelLayoutProvider),
        ChatPanelLayout.full,
      );
    });

    test('until the student chooses, the panel follows a resize', () {
      final c = container();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);

      c.read(windowWidth.notifier).state = _narrow;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

      c.read(windowWidth.notifier).state = _wide;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
    });

    test('a stored false keeps the panel open on a narrow window', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: false});
      final c = container(width: _narrow);
      c.read(chatCollapsedProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
    });

    test('a stored true keeps the panel folded on a wide window', () async {
      SharedPreferences.setMockInitialValues({kChatCollapsedPrefsKey: true});
      final c = container(width: _wide);
      c.read(chatCollapsedProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
    });

    test('once the student chooses, the window no longer matters', () async {
      final c = container(width: _narrow);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

      await c.read(chatCollapsedProvider.notifier).expand();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
      c.read(windowWidth.notifier).state = _wide;
      c.read(windowWidth.notifier).state = _narrow;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);

      await c.read(chatCollapsedProvider.notifier).collapse();
      c.read(windowWidth.notifier).state = _wide;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
    });

    test('the window fallback is a theory-view thing: practice stays full, '
        'playground stays hidden', () {
      expect(
        container(
          mode: SessionMode.practice,
          width: _narrow,
        ).read(chatPanelLayoutProvider),
        ChatPanelLayout.full,
      );
      expect(
        container(
          mode: SessionMode.playground,
          width: _narrow,
        ).read(chatPanelLayoutProvider),
        ChatPanelLayout.hidden,
      );
    });

    test('practice ignores the flag: the panel is always full', () async {
      final c = container(mode: SessionMode.practice);
      await c.read(chatCollapsedProvider.notifier).collapse();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
    });

    test('playground still hides the panel, flag or no flag', () async {
      final c = container(mode: SessionMode.playground);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.hidden);
      await c.read(chatCollapsedProvider.notifier).collapse();
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.hidden);
    });

    test('an MCQ on screen hides the panel even in a folded explain', () async {
      final c = container();
      await c.read(chatCollapsedProvider.notifier).collapse();
      c.read(activeMcqProvider.notifier).state = _mcq;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.hidden);
      c.read(activeMcqProvider.notifier).state = null;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
    });

    test(
      'leaving explain shows the full panel; coming back re-folds',
      () async {
        final c = container();
        await c.read(chatCollapsedProvider.notifier).collapse();
        expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

        c.read(modeProvider.notifier).state = SessionMode.practice;
        expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);

        c.read(modeProvider.notifier).state = SessionMode.explain;
        expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
      },
    );
  });

  group('windowWidthProvider', () {
    testWidgets('reads the window in logical pixels and follows a resize', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2000, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(windowWidthProvider), 1000);

      tester.view.physicalSize = const Size(2800, 1400);
      await tester.pump(Duration.zero);
      expect(c.read(windowWidthProvider), 1400);
    });

    testWidgets('a narrow window folds an undecided theory view through the '
        'real provider', (tester) async {
      tester.view.physicalSize = const Size(_narrow, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [modeProvider.overrideWith((_) => SessionMode.explain)],
      );
      addTearDown(c.dispose);

      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

      tester.view.physicalSize = const Size(_wide, 700);
      await tester.pump(Duration.zero);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
    });
  });

  group('chatUnreadProvider', () {
    late ChatService chat;

    setUp(() => chat = ChatService());
    tearDown(() => chat.dispose());

    test('a message that lands behind the window fold is unread too', () {
      final c = container(chat: chat, width: _narrow);
      c.read(chatUnreadProvider);
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);

      chat.addTutorMessage('hello');
      expect(c.read(chatUnreadProvider), isTrue);

      // Widening the window unfolds the undecided panel: read.
      c.read(windowWidth.notifier).state = _wide;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.full);
      expect(c.read(chatUnreadProvider), isFalse);
    });

    test(
      'a tutor message while folded raises the flag; unfolding clears it',
      () async {
        final c = container(chat: chat);
        await c.read(chatCollapsedProvider.notifier).collapse();
        expect(c.read(chatUnreadProvider), isFalse);

        chat.addTutorMessage('Have a look at the second paragraph.');
        expect(c.read(chatUnreadProvider), isTrue);

        await c.read(chatCollapsedProvider.notifier).expand();
        expect(c.read(chatUnreadProvider), isFalse);
      },
    );

    test(
      'a streamed reply counts once it completes, not while in flight',
      () async {
        final c = container(chat: chat);
        await c.read(chatCollapsedProvider.notifier).collapse();
        c.read(chatUnreadProvider);

        chat.startStream();
        chat.updateStream('Well');
        expect(c.read(chatUnreadProvider), isFalse);

        chat.completeStream('Well done.');
        expect(c.read(chatUnreadProvider), isTrue);
      },
    );

    test(
      'a stream that ends empty, a notice, or a failed stream is not unread',
      () async {
        final c = container(chat: chat);
        await c.read(chatCollapsedProvider.notifier).collapse();
        c.read(chatUnreadProvider);

        chat.startStream();
        chat.completeStream('   ');
        chat.startStream();
        chat.failStream();
        chat.addSystemNotice(const ChatNotice(ChatNoticeKind.noGoalsLeft));
        expect(c.read(chatUnreadProvider), isFalse);
      },
    );

    test('a tutor message while the panel is on screen is not unread', () {
      final c = container(chat: chat);
      c.read(chatUnreadProvider);
      chat.addTutorMessage('hello');
      expect(c.read(chatUnreadProvider), isFalse);
    });

    test('a message while the panel is hidden waits for the strip', () async {
      final c = container(mode: SessionMode.playground, chat: chat);
      await c.read(chatCollapsedProvider.notifier).collapse();
      c.read(chatUnreadProvider);

      chat.addTutorMessage('hello');
      expect(c.read(chatUnreadProvider), isTrue);

      // Back in the folded theory view the dot is still owed.
      c.read(modeProvider.notifier).state = SessionMode.explain;
      expect(c.read(chatPanelLayoutProvider), ChatPanelLayout.collapsed);
      expect(c.read(chatUnreadProvider), isTrue);

      // Practice shows the full panel: read.
      c.read(modeProvider.notifier).state = SessionMode.practice;
      expect(c.read(chatUnreadProvider), isFalse);
    });

    test(
      'emptying the chat (a restart) drops the flag: nothing left to read',
      () async {
        final c = container(chat: chat);
        await c.read(chatCollapsedProvider.notifier).collapse();
        c.read(chatUnreadProvider);

        chat.addTutorMessage('hello');
        expect(c.read(chatUnreadProvider), isTrue);
        chat.clear();
        expect(c.read(chatUnreadProvider), isFalse);

        // The first message of the new session is unread again.
        chat.addTutorMessage('hello again');
        expect(c.read(chatUnreadProvider), isTrue);
      },
    );
  });
}
