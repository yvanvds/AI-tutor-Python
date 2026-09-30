// Issue #211 — the "Goal reached!" splash names the subgoal in the app
// language: its English title and description when the goal has a
// translation, the Dutch text, without a notice, when it has none. The
// splash keeps the goal's id, so a translation that arrives on a poll and a
// language switch while it is up both apply at once. In Dutch nothing is
// fetched from `translations`.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
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
);

Map<String, dynamic> _english() => Translation.goal(
  language: 'en',
  goalId: 's2',
  title: 'Variables',
  description: 'Keeping values under a name.',
  sourceHash: goalSourceHash(_variabelen),
).toMap();

/// The splash as `TutorService` raises it: the goal's id and Dutch text.
GoalSplashState _splash() => GoalSplashState(
  goalId: _variabelen.id,
  goalTitle: _variabelen.title,
  description: _variabelen.description!,
  phraseIndex: 0,
);

/// Stands in for the Options language switch.
final _locale = StateProvider<Locale>((_) => const Locale('en'));

/// The real service, recording every language it was asked to fetch.
class _RecordingTranslations extends TranslationService {
  _RecordingTranslations(InMemoryCosmos store)
    : super(container: store.container);

  final List<String> fetched = [];

  @override
  Future<List<Translation>> listLanguage(String language) {
    fetched.add(language);
    return super.listLanguage(language);
  }
}

void main() {
  late InMemoryCosmos store;
  late _RecordingTranslations service;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryCosmos.partitioned('language', [_english()]);
    service = _RecordingTranslations(store);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> mount(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _locale.overrideWith((_) => locale),
          appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
          translationServiceProvider.overrideWithValue(service),
          splashStateProvider.overrideWith((_) => _splash()),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(_locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: GoalSplashOverlay()),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(GoalSplashOverlay)),
    );
    await settle(tester);
  }

  /// Disposes the scope, and with it the `translations` poll.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('English with a translation: the goal in English', (
    tester,
  ) async {
    await mount(tester, const Locale('en'));

    expect(find.text('Goal reached!'), findsOneWidget);
    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('Keeping values under a name.'), findsOneWidget);
    expect(find.text('Variabelen'), findsNothing);
    expect(find.text('Waarden onthouden onder een naam.'), findsNothing);

    await unmount(tester);
  });

  testWidgets('English without a translation: the goal in Dutch, without a '
      'notice, until a translation arrives on a later poll', (tester) async {
    store.docs.clear();
    await mount(tester, const Locale('en'));

    expect(find.text('Goal reached!'), findsOneWidget);
    expect(find.text('Variabelen'), findsOneWidget);
    expect(find.text('Waarden onthouden onder een naam.'), findsOneWidget);
    expect(find.textContaining('translat'), findsNothing);
    expect(find.textContaining('Dutch'), findsNothing);

    store.upsert(_english(), partitionKey: 'en');
    await tester.pump(kCosmosPollInterval);
    await settle(tester);

    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('Keeping values under a name.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Dutch: the goal as written, and nothing fetched', (
    tester,
  ) async {
    await mount(tester, const Locale('nl'));

    expect(find.text('Doel bereikt!'), findsOneWidget);
    expect(find.text('Variabelen'), findsOneWidget);
    expect(find.text('Waarden onthouden onder een naam.'), findsOneWidget);
    expect(find.text('Variables'), findsNothing);
    expect(service.fetched, isEmpty);

    await unmount(tester);
  });

  testWidgets('a language switch while the splash is up renames the goal '
      'at once', (tester) async {
    await mount(tester, const Locale('en'));
    expect(find.text('Variables'), findsOneWidget);

    container.read(_locale.notifier).state = const Locale('nl');
    await settle(tester);

    expect(find.text('Doel bereikt!'), findsOneWidget);
    expect(find.text('Variabelen'), findsOneWidget);
    expect(find.text('Waarden onthouden onder een naam.'), findsOneWidget);
    expect(find.text('Variables'), findsNothing);

    container.read(_locale.notifier).state = const Locale('en');
    await settle(tester);

    expect(find.text('Goal reached!'), findsOneWidget);
    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('Keeping values under a name.'), findsOneWidget);

    await unmount(tester);
  });
}
