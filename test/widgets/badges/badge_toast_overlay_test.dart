// Issue #220 — the notice for a badge just earned: the badge's name, its
// tier and what it counts; one summary for the first look or several badges
// at once; a close button and a link to the trophy case; it goes by itself
// after a while, and it waits while the level-up or the goal splash is up.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
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

void main() {
  late ProviderContainer container;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(
              container: InMemoryCosmos.partitioned('language').container,
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(children: [SizedBox.expand(), BadgeToastOverlay()]),
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
}
