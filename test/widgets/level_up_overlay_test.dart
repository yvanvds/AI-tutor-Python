// Issue #211 — the level-up celebration's "You've mastered {concept}." names
// the mastered subgoal in the app language: its English title when the goal
// has a translation, the Dutch title, without a notice, when it has none. The
// event keeps the goal's id, so a language switch while the card is up
// renames the concept at once. A moment that is not about a goal (the debug
// push, no id) shows its concept name as it is.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cosmos.dart';

final _variabelen = Goal(
  id: 's2',
  title: 'Variabelen',
  description: 'Waarden onthouden onder een naam.',
  parentId: 'r1',
  order: 2000,
  kind: 'concept',
);

Map<String, dynamic> _english() => Translation.goal(
  language: 'en',
  goalId: 's2',
  title: 'Variables',
  description: 'Keeping values under a name.',
  sourceHash: goalSourceHash(_variabelen),
).toMap();

/// Stands in for the Options language switch.
final _locale = StateProvider<Locale>((_) => const Locale('en'));

void main() {
  late InMemoryCosmos store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryCosmos.partitioned('language', [_english()]);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    // The card's fade and pop.
    await tester.pump(const Duration(seconds: 1));
  }

  /// Mounts the overlay and raises the moment the way `TutorService` arms
  /// it for a mastered concept goal: its Dutch title and its id.
  Future<void> celebrate(
    WidgetTester tester,
    Locale locale, {
    String? goalId = 's2',
    String conceptName = 'Variabelen',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _locale.overrideWith((_) => locale),
          appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
          translationServiceProvider.overrideWithValue(
            TranslationService(container: store.container),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(_locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LevelUpOverlay()),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(LevelUpOverlay)),
    );
    container
        .read(levelUpControllerProvider.notifier)
        .push(
          LevelUpEvent(
            newLevel: 2,
            xpAwarded: 100,
            conceptName: conceptName,
            goalId: goalId,
          ),
        );
    await settle(tester);
  }

  /// Disposes the scope, and with it the `translations` poll.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('English with a translation: the concept in English', (
    tester,
  ) async {
    await celebrate(tester, const Locale('en'));

    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text("You've mastered Variables."), findsOneWidget);
    expect(find.textContaining('Variabelen'), findsNothing);

    await unmount(tester);
  });

  testWidgets('English without a translation: the Dutch title, without a '
      'notice', (tester) async {
    store.docs.clear();
    await celebrate(tester, const Locale('en'));

    expect(find.text("You've mastered Variabelen."), findsOneWidget);
    expect(find.textContaining('translat'), findsNothing);
    expect(find.textContaining('Dutch'), findsNothing);

    await unmount(tester);
  });

  testWidgets('Dutch: the concept as written', (tester) async {
    await celebrate(tester, const Locale('nl'));

    expect(find.text('Je hebt Variabelen onder de knie.'), findsOneWidget);
    expect(find.textContaining('Variables'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a language switch while the card is up renames the concept', (
    tester,
  ) async {
    await celebrate(tester, const Locale('nl'));
    expect(find.text('Je hebt Variabelen onder de knie.'), findsOneWidget);

    container.read(_locale.notifier).state = const Locale('en');
    await settle(tester);

    expect(find.text("You've mastered Variables."), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a moment without a goal shows its concept name as it is', (
    tester,
  ) async {
    await celebrate(
      tester,
      const Locale('en'),
      goalId: null,
      conceptName: 'elif-ladder',
    );

    expect(find.text("You've mastered elif-ladder."), findsOneWidget);

    await unmount(tester);
  });
}
