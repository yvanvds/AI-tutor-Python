// Issue #220 — the notice for a badge just earned: the badge's name, its
// tier and what it counts; one summary for the first look or several badges
// at once; a close button and a link to the trophy case; it goes by itself
// after a while, and it waits while the level-up or the goal splash is up.
//
// Issue #283 — where it goes: over the chat's messages in the session, as
// wide as the chat allows; in the corner on the other pages and beside the
// folded chat's strip; nowhere yet in the playground, where it waits. The
// real window sizes are the integration flow's (`badge_toast_place.dart`).

import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/badges/badge_toast_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

EarnedBadgeNotice _notice(String id, int tier) =>
    EarnedBadgeNotice(badge: BadgeCatalog.byId(id)!, tier: tier);

/// How the chat panel is drawn in a test: folded, as in the theory view of
/// a small window, unless a test opens or hides it.
final _layout = StateProvider<ChatPanelLayout>(
  (_) => ChatPanelLayout.collapsed,
);

/// The width of the chat panel next to the exercise in a 700 px window:
/// half of the 628 px the sidebar leaves (#259).
const double _narrowChat = 314;

void main() {
  late ProviderContainer container;

  /// The shell's stack with the corner's host, and a chat [chatWidth] wide
  /// along the right edge, its messages from y 100 down with the other host
  /// over them; a tap on the messages counts in [chatTaps].
  Future<void> mount(
    WidgetTester tester, {
    double chatWidth = _narrowChat,
    List<int>? chatTaps,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(
              container: InMemoryCosmos.partitioned('language').container,
            ),
          ),
          chatPanelLayoutProvider.overrideWith((ref) => ref.watch(_layout)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                Positioned(
                  key: const ValueKey('messages'),
                  top: 100,
                  right: 0,
                  bottom: 0,
                  width: chatWidth,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => chatTaps?.add(1),
                      ),
                      const BadgeToastOverChat(),
                    ],
                  ),
                ),
                const BadgeToastOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(BadgeToastOverlay)),
    );
  }

  void queue(BadgeAnnouncement a) =>
      container.read(badgeAnnouncementsProvider.notifier).preview(a);

  Finder toast() => find.byKey(const ValueKey('badge-toast'));

  Finder overChat() =>
      find.descendant(of: find.byType(BadgeToastOverChat), matching: toast());

  void chatAs(ChatPanelLayout layout) =>
      container.read(_layout.notifier).state = layout;

  Rect window(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  Rect messages(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('messages')));

  /// The card's slide-in, a frame of the confetti.
  Future<void> show(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('one badge: its name, its tier and what it counts', (
    tester,
  ) async {
    await mount(tester);
    expect(toast(), findsNothing);
    queue(BadgeAnnouncement(badges: [_notice('effort', 2)]));
    await show(tester);

    expect(toast(), findsOneWidget);
    expect(find.text('NEW BADGE'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    expect(
      find.text('Tier 2 · Exercises done, right or wrong.'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('the first look: one summary, "already earned"', (tester) async {
    await mount(tester);
    queue(
      BadgeAnnouncement(
        badges: [
          _notice('effort', 1),
          _notice('streak', 1),
          _notice('helloWorld', 1),
        ],
        first: true,
      ),
    );
    await show(tester);
    expect(find.text("You've already earned 3 badges!"), findsOneWidget);
    expect(find.text('Effort, On a roll, Hello, World!'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('several at once later: "new badges"', (tester) async {
    await mount(tester);
    queue(
      BadgeAnnouncement(
        badges: [
          _notice('effort', 3),
          _notice('fortyTwo', 1),
          _notice('offByOne', 1),
        ],
      ),
    );
    await show(tester);
    expect(find.text('3 new badges!'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('closing it brings up the next one waiting', (tester) async {
    await mount(tester);
    queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
    queue(BadgeAnnouncement(badges: [_notice('helloWorld', 1)]));
    await show(tester);
    expect(find.text('Effort'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await show(tester);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Hello, World!'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('it goes by itself after a while', (tester) async {
    await mount(tester);
    queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
    await show(tester);

    await tester.pump(kBadgeToastDuration - const Duration(seconds: 1));
    expect(toast(), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(toast(), findsNothing);
    expect(container.read(badgeAnnouncementsProvider), isEmpty);
    await unmount(tester);
  });

  testWidgets('"See your trophy case" opens it', (tester) async {
    await mount(tester);
    queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
    await show(tester);
    await tester.tap(find.text('See your trophy case'));
    await tester.pump();
    expect(container.read(sectionProvider), Section.trophies);
    expect(container.read(badgeAnnouncementsProvider), isEmpty);
    await unmount(tester);
  });

  testWidgets('it waits while the level-up or the goal splash is up, and '
      'shows after', (tester) async {
    await mount(tester);
    container
        .read(levelUpControllerProvider.notifier)
        .push(const LevelUpEvent(newLevel: 3, xpAwarded: 20, conceptName: 'x'));
    queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
    await show(tester);
    expect(toast(), findsNothing);
    // Longer than it would have stayed: it was never up, so it is not gone.
    await tester.pump(kBadgeSummaryToastDuration);
    expect(container.read(badgeAnnouncementsProvider), hasLength(1));

    container.read(levelUpControllerProvider.notifier).dismiss();
    container.read(splashStateProvider.notifier).state = GoalSplashState(
      goalId: 's1',
      goalTitle: 'Print',
      description: '',
      phraseIndex: 0,
    );
    await show(tester);
    expect(toast(), findsNothing);

    container.read(splashStateProvider.notifier).state = null;
    await show(tester);
    expect(toast(), findsOneWidget);
    await unmount(tester);
  });

  group('where it goes (#283)', () {
    testWidgets('outside the session: in the corner under the top bar, at '
        'its full width', (tester) async {
      await mount(tester);
      container.read(sectionProvider.notifier).state = Section.map;
      queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
      await show(tester);

      final rect = tester.getRect(toast());
      expect(rect.width, kBadgeToastWidth);
      expect(rect.right, window(tester).right - 16);
      expect(rect.top, topBarHeight + 12);
      expect(overChat(), findsNothing);
      await unmount(tester);
    });

    testWidgets('in the theory view with the chat folded: beside the strip, '
        'not over its button', (tester) async {
      await mount(tester);
      queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
      await show(tester);

      expect(container.read(sectionProvider), Section.session);
      expect(tester.getRect(toast()).right, window(tester).right - 32 - 16);
      await unmount(tester);
    });

    testWidgets('over a narrow chat: under nothing but its messages, as wide '
        'as the chat less its margins, and the messages take a tap beside '
        'it', (tester) async {
      final taps = <int>[];
      await mount(tester, chatTaps: taps);
      chatAs(ChatPanelLayout.full);
      queue(BadgeAnnouncement(badges: [_notice('effort', 2)]));
      await show(tester);

      expect(toast(), findsOneWidget);
      expect(overChat(), findsOneWidget, reason: 'not in the corner');
      final chat = messages(tester);
      final rect = tester.getRect(toast());
      expect(rect.width, _narrowChat - 2 * kBadgeToastChatInset);
      expect(rect.left, chat.left + kBadgeToastChatInset);
      expect(rect.right, chat.right - kBadgeToastChatInset);
      expect(rect.top, chat.top + kBadgeToastChatInset);
      // Still whole: its words and its buttons.
      expect(find.text('Effort'), findsOneWidget);
      expect(
        find.text('Tier 2 · Exercises done, right or wrong.'),
        findsOneWidget,
      );
      for (final part in [
        find.text('See your trophy case'),
        find.byTooltip('Close'),
      ]) {
        final r = tester.getRect(part);
        expect(
          r.left >= rect.left && r.right <= rect.right,
          isTrue,
          reason: '${part.describeMatch(Plurality.one)} inside the card',
        );
      }
      await tester.tapAt(Offset(chat.center.dx, rect.bottom + 20));
      expect(taps, hasLength(1));
      await unmount(tester);
    });

    testWidgets('over a wide chat: at its full width in the top right corner '
        'of the messages, which take the mouse beside it', (tester) async {
      final taps = <int>[];
      await mount(tester, chatWidth: 460, chatTaps: taps);
      chatAs(ChatPanelLayout.full);
      queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
      await show(tester);

      final chat = messages(tester);
      final rect = tester.getRect(toast());
      expect(rect.width, kBadgeToastWidth);
      expect(rect.right, chat.right - kBadgeToastChatInset);
      expect(rect.top, chat.top + kBadgeToastChatInset);
      await tester.tapAt(Offset(chat.left + 30, rect.center.dy));
      expect(taps, hasLength(1));
      await unmount(tester);
    });

    testWidgets('in the playground it waits, its time not running, and '
        'shows once there is a place for it', (tester) async {
      await mount(tester);
      chatAs(ChatPanelLayout.hidden);
      queue(BadgeAnnouncement(badges: [_notice('effort', 1)]));
      await show(tester);
      expect(toast(), findsNothing);
      await tester.pump(kBadgeSummaryToastDuration);
      expect(container.read(badgeAnnouncementsProvider), hasLength(1));

      chatAs(ChatPanelLayout.full);
      await show(tester);
      expect(overChat(), findsOneWidget);
      // Up for its own time from here.
      await tester.pump(kBadgeToastDuration - const Duration(seconds: 1));
      expect(toast(), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(toast(), findsNothing);
      await unmount(tester);
    });
  });

  group('the place, from the page and the chat panel (#283)', () {
    test('in the session: over the open chat, in the corner beside the '
        'folded one, waiting where there is none', () {
      expect(
        badgeToastPlaceFor(Section.session, ChatPanelLayout.full),
        BadgeToastPlace.chat,
      );
      expect(
        badgeToastPlaceFor(Section.session, ChatPanelLayout.collapsed),
        BadgeToastPlace.corner,
      );
      expect(
        badgeToastPlaceFor(Section.session, ChatPanelLayout.hidden),
        BadgeToastPlace.waiting,
      );
    });

    test('on every other page: the corner', () {
      for (final section in Section.values.where((s) => s != Section.session)) {
        for (final panel in ChatPanelLayout.values) {
          expect(
            badgeToastPlaceFor(section, panel),
            BadgeToastPlace.corner,
            reason: '$section, $panel',
          );
        }
      }
    });
  });
}
