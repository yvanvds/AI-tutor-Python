// Issue #220 — the trophy case: earned badges with their tier and the way to
// the next one ("152/250"), the ones not earned yet in grey, a secret as a
// "?" without its name or rule until it is found, a "Kenner van …" per
// hoofddoel with its LOs counted, the lesson badges waiting for lesson
// times, and the credits of the icons.

import 'package:ai_tutor_python/features/badges/badge_proof_sheet.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

final _root = Goal(id: 'r1', title: 'Lussen', order: 0);

BadgeBoard _board({
  BadgeFacts? facts = const BadgeFacts(
    oefeningen: 152,
    correctOefeningen: 120,
    hardCorrect: 12,
    experts: {'r1': (mastered: 12, total: 15)},
    keyDisputes: 1,
  ),
  Map<String, EarnedBadge> earned = const {
    'effort': EarnedBadge(tier: 2),
    'helloWorld': EarnedBadge(tier: 1),
    'fortyTwo': EarnedBadge(tier: 1),
    'offByOne': EarnedBadge(tier: 1),
    'bugHunter': EarnedBadge(tier: 1),
  },
}) => BadgeBoard.from(
  BadgeSnapshot(facts: facts, roots: [_root]),
  EarnedBadges(earned),
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(
              container: InMemoryCosmos.partitioned('language').container,
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tile(String id) => find.byKey(ValueKey('badge-tile-$id'));

  Finder inTile(String id, Finder what) =>
      find.descendant(of: tile(id), matching: what);

  testWidgets('says what badges are, and are not', (tester) async {
    await mount(tester, PrijzenkastView(board: _board()));
    expect(find.text('Trophy case'), findsOneWidget);
    expect(
      find.text(
        "Badges for what you've done. They give no XP and don't count "
        'towards your grade.',
      ),
      findsOneWidget,
    );
    expect(find.text('5 of 34 badges earned'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an earned badge: its tier and the way to the next', (
    tester,
  ) async {
    await mount(tester, PrijzenkastView(board: _board()));
    expect(inTile('effort', find.text('Effort')), findsOneWidget);
    expect(inTile('effort', find.text('Tier 2 of 6')), findsOneWidget);
    expect(inTile('effort', find.text('152/250')), findsOneWidget);
    final frame = tester.widget<BadgeFrame>(
      inTile('effort', find.byType(BadgeFrame)),
    );
    expect(frame.size, 64);
    expect(frame.hidden, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('not earned yet: grey, with the way to the first tier', (
    tester,
  ) async {
    await mount(tester, PrijzenkastView(board: _board()));
    expect(inTile('hardCorrect', find.text('Not earned yet')), findsOneWidget);
    expect(inTile('hardCorrect', find.text('12/100')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a secret: a "?" with no name and no rule until it is found; '
      'found, it shows both', (tester) async {
    await mount(tester, PrijzenkastView(board: _board()));
    expect(inTile('rubberDuck', find.text('Secret badge')), findsOneWidget);
    expect(
      inTile('rubberDuck', find.text('Find out yourself how to get this one.')),
      findsOneWidget,
    );
    expect(find.text('Rubber duck'), findsNothing);
    expect(find.text('You asked the tutor a question yourself.'), findsNothing);
    expect(
      tester
          .widget<BadgeFrame>(inTile('rubberDuck', find.byType(BadgeFrame)))
          .hidden,
      isTrue,
    );

    expect(inTile('bugHunter', find.text('Bug hunter')), findsOneWidget);
    expect(
      inTile('bugHunter', find.text("You were right, the computer wasn't.")),
      findsOneWidget,
    );
    expect(inTile('bugHunter', find.text('Earned')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('"Hello, World!" is no secret', (tester) async {
    await mount(
      tester,
      PrijzenkastView(
        board: _board(facts: BadgeFacts.empty, earned: const {}),
      ),
    );
    expect(inTile('helloWorld', find.text('Hello, World!')), findsOneWidget);
    expect(inTile('helloWorld', find.text('Not earned yet')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a "Kenner van …" per hoofddoel, its LOs counted', (
    tester,
  ) async {
    await mount(tester, PrijzenkastView(board: _board()));
    final id = expertBadgeId('r1');
    expect(inTile(id, find.text('Expert in Lussen')), findsOneWidget);
    expect(inTile(id, find.text('12/15')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the lesson badges wait for the class\'s lesson times', (
    tester,
  ) async {
    await mount(tester, PrijzenkastView(board: _board()));
    for (final id in ['homeWork', 'lessonWeeks']) {
      expect(
        inTile(
          id,
          find.text('Your class has no lesson times yet, so this one waits.'),
        ),
        findsOneWidget,
        reason: id,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a history that could not be read: the badges earned, no '
      'progress claimed', (tester) async {
    await mount(tester, PrijzenkastView(board: _board(facts: null)));
    expect(
      find.text(
        'Your progress could not be loaded. You see the badges you already '
        'have.',
      ),
      findsOneWidget,
    );
    expect(inTile('effort', find.text('Tier 2 of 6')), findsOneWidget);
    expect(find.text('152/250'), findsNothing);
    expect(
      find.text('Your class has no lesson times yet, so this one waits.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('while the badges are counted, it says so', (tester) async {
    await mount(tester, const PrijzenkastView(board: null));
    expect(find.text('Counting your badges…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the page shows the signed-in student\'s board', (tester) async {
    await mount(
      tester,
      const PrijzenkastPage(),
      overrides: [badgeBoardProvider.overrideWithValue(_board())],
    );
    expect(inTile('effort', find.text('Tier 2 of 6')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the credits of the icons are one tap away', (tester) async {
    await mount(tester, PrijzenkastView(board: _board()));
    await tester.tap(find.text('Icons: game-icons.net (CC BY 3.0)'));
    await tester.pumpAndSettle();
    expect(find.text('Badge icons'), findsOneWidget);
    expect(find.text('Weight lifting up by Delapouite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the proof sheet\'s example case renders every badge', (
    tester,
  ) async {
    await mount(tester, PrijzenkastView(board: demoBadgeBoard()));
    expect(
      find.byType(BadgeTileCard),
      findsNWidgets(BadgeCatalog.all(expertGoalIds: ['x']).length),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
