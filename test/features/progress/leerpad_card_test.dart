// Issue #161 — the leerpad's "finished" marks come from the `advancedAt`
// stamp on the progress doc, while every bar keeps the honest mastered
// fraction. A subgoal the conductor advanced past with a stuck LO shows its
// check mark *and* a bar short of 100%; the root reads "completed" only once
// every required subgoal has been advanced past, whatever its average bar.
// A doc from before the stamp existed (1.0, no stamp) still counts as
// finished, and a half-mastered subgoal without the stamp is simply open.
//
// Issue #210 — the card's root title and description and its chips' titles
// are in the app language when the goal has a translation, and in Dutch,
// without a notice, when it has none. Dutch fetches no translations.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

final _root = Goal(id: 'r', title: 'Basics', order: 0);
final _print = Goal(id: 's1', title: 'Print', parentId: 'r', order: 1);
final _vars = Goal(id: 's2', title: 'Variables', parentId: 'r', order: 2);
final _stamp = DateTime.utc(2026, 9, 23, 10);

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

Widget _card(
  Map<String, Progress> progressById, {
  Goal? root,
  List<Goal>? children,
  Locale locale = const Locale('en'),
  TranslationService? translations,
}) => ProviderScope(
  overrides: [
    appLocaleProvider.overrideWithValue(locale),
    translationServiceProvider.overrideWithValue(
      translations ??
          TranslationService(
            container: InMemoryCosmos.partitioned('language').container,
          ),
    ),
  ],
  child: localizedTestApp(
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LeerpadCard(
          index: 1,
          root: root ?? _root,
          children: children ?? [_print, _vars],
          progressById: progressById,
          isActive: true,
          onContinue: () {},
        ),
      ),
    ),
    locale: locale,
  ),
);

Finder _chip(String goalId) =>
    find.byWidgetPredicate((w) => w is LeerpadChildChip && w.goal.id == goalId);

Finder _in(Finder chip, Finder what) =>
    find.descendant(of: chip, matching: what);

final _check = find.byIcon(Icons.check_circle);

void main() {
  testWidgets('a subgoal advanced past with a stuck LO shows its check mark '
      'on a bar short of 100%, and the root is completed on the stamps, not '
      'on its average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp),
        's2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp),
      }),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('50%')), findsOneWidget);
    expect(_in(_chip('s2'), _check), findsOneWidget);
    expect(_in(_chip('s1'), find.text('100%')), findsOneWidget);
    expect(_in(_chip('s1'), _check), findsOneWidget);
    // Both required subgoals were advanced past: the root reads completed
    // even though its average bar is 75%.
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('75%'), findsNothing);
  });

  testWidgets('a half-mastered subgoal without the stamp is open, a '
      'pre-stamp full bar still counts as finished, and the root shows its '
      'average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0),
        's2': Progress(goalID: 's2', progress: 0.5),
      }),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('50%')), findsOneWidget);
    expect(_in(_chip('s2'), _check), findsNothing);
    expect(_in(_chip('s1'), _check), findsOneWidget);
    expect(find.text('completed'), findsNothing);
    expect(find.text('75%'), findsOneWidget);
  });

  group('titles in the app language (#210)', () {
    final root = Goal(
      id: 'r',
      title: 'Basis',
      description: 'Je eerste stappen in Python.',
      order: 0,
    );
    final printen = Goal(id: 's1', title: 'Printen', parentId: 'r', order: 1);
    final variabelen = Goal(
      id: 's2',
      title: 'Variabelen',
      parentId: 'r',
      order: 2,
    );

    late InMemoryCosmos store;
    late _RecordingTranslations service;

    setUp(() {
      store = InMemoryCosmos.partitioned('language', [
        Translation.goal(
          language: 'en',
          goalId: 'r',
          title: 'Basics',
          description: 'Your first steps in Python.',
          sourceHash: goalSourceHash(root),
        ).toMap(),
        Translation.goal(
          language: 'en',
          goalId: 's1',
          title: 'Printing',
          description: '',
          sourceHash: goalSourceHash(printen),
        ).toMap(),
      ]);
      service = _RecordingTranslations(store);
    });

    Widget card(Locale locale) => _card(
      const {},
      root: root,
      children: [printen, variabelen],
      locale: locale,
      translations: service,
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    testWidgets('English: the translated root and chip in English, the '
        'untranslated chip in Dutch without a notice', (tester) async {
      await tester.pumpWidget(card(const Locale('en')));
      await settle(tester);

      expect(find.text('Basics'), findsOneWidget);
      expect(find.text('Your first steps in Python.'), findsOneWidget);
      expect(find.text('Basis'), findsNothing);
      expect(find.text('Je eerste stappen in Python.'), findsNothing);
      expect(_in(_chip('s1'), find.text('Printing')), findsOneWidget);
      expect(_in(_chip('s2'), find.text('Variabelen')), findsOneWidget);
      expect(find.textContaining('translat'), findsNothing);
      expect(find.textContaining('Dutch'), findsNothing);
    });

    testWidgets('English without translations: everything in Dutch, as '
        'written', (tester) async {
      store.docs.clear();
      await tester.pumpWidget(card(const Locale('en')));
      await settle(tester);

      expect(find.text('Basis'), findsOneWidget);
      expect(find.text('Je eerste stappen in Python.'), findsOneWidget);
      expect(_in(_chip('s1'), find.text('Printen')), findsOneWidget);
      expect(_in(_chip('s2'), find.text('Variabelen')), findsOneWidget);
    });

    testWidgets('a translation that arrives on a later poll replaces the '
        'Dutch title', (tester) async {
      store.delete(Translation.goalDocId('s1'), partitionKey: 'en');
      await tester.pumpWidget(card(const Locale('en')));
      await settle(tester);
      expect(_in(_chip('s1'), find.text('Printen')), findsOneWidget);

      store.upsert(
        Translation.goal(
          language: 'en',
          goalId: 's1',
          title: 'Printing',
          description: '',
          sourceHash: goalSourceHash(printen),
        ).toMap(),
        partitionKey: 'en',
      );
      await tester.pump(kCosmosPollInterval);
      await settle(tester);

      expect(_in(_chip('s1'), find.text('Printing')), findsOneWidget);
    });

    testWidgets('Dutch: the goals as written, and nothing fetched', (
      tester,
    ) async {
      await tester.pumpWidget(card(const Locale('nl')));
      await settle(tester);

      expect(find.text('Basis'), findsOneWidget);
      expect(find.text('Je eerste stappen in Python.'), findsOneWidget);
      expect(_in(_chip('s1'), find.text('Printen')), findsOneWidget);
      expect(find.text('Basics'), findsNothing);
      expect(service.fetched, isEmpty);
    });
  });
}
