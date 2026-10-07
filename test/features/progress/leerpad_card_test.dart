// Issue #161 — the leerpad's "finished" marks come from the `advancedAt`
// stamp on the progress doc, while every bar keeps an honest count. A
// subgoal the conductor advanced past with a stuck LO shows its check mark
// *and* a bar short of 100%; the root reads "completed" only once every
// required subgoal has been advanced past, whatever its average bar. A doc
// from before the stamp existed (1.0, no stamp) still counts as finished,
// and a half-mastered subgoal without the stamp is simply open.
//
// Issue #243 — the bars and the "x of y demonstrated" under each chip
// count the mastery stamps the grade reads (`firstMasteredAt`), not the
// cached `progress`: a subgoal finished before #161 with an open LO reads
// short of full. A completed goal shows its chips too. A chip opens the
// list of its learning objectives, each "demonstrated" or "not yet
// demonstrated", with nothing to press; a statement is in the app language
// when it has a translation. Without stamps (loading, a failed read) the
// bars fall back on the cache and no count shows.
//
// Issue #210 — the card's root title and description and its chips' titles
// are in the app language when the goal has a translation, and in Dutch,
// without a notice, when it has none. Dutch fetches no translations.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_objectives_panel.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/mastery_stamps.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

LearningObjective _lo(String id, String statement, {bool optional = false}) =>
    LearningObjective(
      id: id,
      statement: statement,
      kind: LoKind.apply,
      optional: optional,
    );

final _root = Goal(id: 'r', title: 'Basics', order: 0);
final _print = Goal(
  id: 's1',
  title: 'Print',
  parentId: 'r',
  order: 1,
  objectives: [_lo('lo-print', 'Je kan met print() tekst tonen.')],
);
final _vars = Goal(
  id: 's2',
  title: 'Variables',
  parentId: 'r',
  order: 2,
  objectives: [
    _lo('lo-swap', 'Je kan twee variabelen omwisselen.', optional: true),
    _lo('lo-var', 'Je kan een waarde in een variabele bewaren.'),
    _lo('lo-cast', 'Je kan invoer omzetten naar een getal.'),
  ],
);
final _stamp = DateTime.utc(2026, 9, 23, 10);

/// The mastery stamps on the LOs named as `subgoal/lo`.
MasteryStamps _stamps(List<String> stamped) => MasteryStamps.fromBeliefs([
  for (final key in stamped)
    LoBelief(
      subgoalId: key.split('/').first,
      loId: key.split('/').last,
      alpha: 5,
      beta: 1,
      lastUpdatedAt: _stamp,
      firstMasteredAt: _stamp,
    ),
]);

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
  MasteryStamps? stamps,
  bool isActive = true,
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
          isActive: isActive,
          onContinue: () {},
          stamps: stamps,
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

/// The width of [chip]'s bar, as a share of the track.
double _bar(WidgetTester tester, Finder chip) => tester
    .widget<FractionallySizedBox>(_in(chip, find.byType(FractionallySizedBox)))
    .widthFactor!;

/// The width of the root's bar, as a share of the track.
double _rootBar(WidgetTester tester) => tester
    .widget<AnimatedFractionallySizedBox>(
      find.byType(AnimatedFractionallySizedBox),
    )
    .widthFactor!;

final _panel = find.byType(LeerpadObjectivesPanel);

/// The row of the learning objective whose statement reads [statement].
Finder _row(String statement) => find.ancestor(
  of: find.text(statement),
  matching: find.byType(LeerpadObjectiveRow),
);

void main() {
  testWidgets('a subgoal advanced past with a stuck LO shows its check mark '
      'on a bar short of 100%, and the root is completed on the stamps, not '
      'on its average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp),
        's2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp),
      }, stamps: _stamps(['s1/lo-print', 's2/lo-var'])),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('1 of 2 demonstrated')), findsOneWidget);
    expect(_bar(tester, _chip('s2')), closeTo(0.5, 1e-9));
    expect(_in(_chip('s2'), _check), findsOneWidget);
    expect(_in(_chip('s1'), find.text('1 of 1 demonstrated')), findsOneWidget);
    expect(_bar(tester, _chip('s1')), closeTo(1.0, 1e-9));
    expect(_in(_chip('s1'), _check), findsOneWidget);
    // Both required subgoals were advanced past: the root reads completed
    // even though its average bar is 75%.
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('75%'), findsNothing);
    expect(_rootBar(tester), closeTo(0.75, 1e-9));
  });

  testWidgets('a half-mastered subgoal without the stamp is open, a '
      'pre-stamp full bar still counts as finished, and the root shows its '
      'average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0),
        's2': Progress(goalID: 's2', progress: 0.5),
      }, stamps: _stamps(['s1/lo-print', 's2/lo-var'])),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('1 of 2 demonstrated')), findsOneWidget);
    expect(_in(_chip('s2'), _check), findsNothing);
    expect(_in(_chip('s1'), _check), findsOneWidget);
    expect(find.text('completed'), findsNothing);
    expect(find.text('75%'), findsOneWidget);
  });

  group('demonstrated, as the grade counts it (#243)', () {
    testWidgets('the bars count the stamps, not the cached progress: a '
        'subgoal finished before #161 with an open LO reads short of full', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card({
          // Finished before #161: the cache was forced to 1.0 although
          // `lo-cast` was never demonstrated, and `lo-print` lost its
          // stamp nowhere — it never had one.
          's1': Progress(goalID: 's1', progress: 1.0),
          's2': Progress(goalID: 's2', progress: 1.0),
        }, stamps: _stamps(['s2/lo-var'])),
      );
      await tester.pumpAndSettle();

      expect(
        _in(_chip('s1'), find.text('0 of 1 demonstrated')),
        findsOneWidget,
      );
      expect(_bar(tester, _chip('s1')), 0.0);
      expect(
        _in(_chip('s2'), find.text('1 of 2 demonstrated')),
        findsOneWidget,
      );
      expect(_bar(tester, _chip('s2')), closeTo(0.5, 1e-9));
      // Still finished, both: "completed", and the bar under it short.
      expect(_in(_chip('s1'), _check), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
      expect(_rootBar(tester), closeTo(0.25, 1e-9));
    });

    testWidgets('without stamps the bars show the cached progress and no '
        'count', (tester) async {
      await tester.pumpWidget(
        _card({'s2': Progress(goalID: 's2', progress: 0.5)}),
      );
      await tester.pumpAndSettle();

      expect(_bar(tester, _chip('s2')), closeTo(0.5, 1e-9));
      expect(find.textContaining('demonstrated'), findsNothing);
      expect(find.text('25%'), findsOneWidget);
    });

    testWidgets('a completed goal that is not the active one shows its '
        'chips, without "Continue"; one not completed shows none', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(
          {
            's1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp),
            's2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp),
          },
          isActive: false,
          stamps: _stamps(['s1/lo-print']),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('completed'), findsOneWidget);
      expect(_chip('s1'), findsOneWidget);
      expect(_chip('s2'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      await tester.pumpWidget(
        _card(
          {'s1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp)},
          isActive: false,
          stamps: _stamps(['s1/lo-print']),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('completed'), findsNothing);
      expect(_chip('s1'), findsNothing);
    });

    testWidgets('a chip opens the "You can …" sentences of its LOs, each '
        'demonstrated or not yet, the optional one last; nothing to press; '
        'another chip swaps the list and the open one closes it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card({
          's1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp),
          's2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp),
        }, stamps: _stamps(['s2/lo-var', 's2/lo-swap'])),
      );
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);

      await tester.tap(_chip('s2'));
      await tester.pumpAndSettle();

      expect(_panel, findsOneWidget);
      final rows = tester
          .widgetList<LeerpadObjectiveRow>(find.byType(LeerpadObjectiveRow))
          .toList();
      expect(rows.map((r) => r.objective.id), ['lo-var', 'lo-cast', 'lo-swap']);
      expect(rows.map((r) => r.demonstrated), [true, false, true]);
      expect(
        find.descendant(
          of: _row('Je kan een waarde in een variabele bewaren.'),
          matching: find.text('demonstrated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Je kan invoer omzetten naar een getal.'),
          matching: find.text('not yet demonstrated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Je kan twee variabelen omwisselen.'),
          matching: find.text('demonstrated · optional'),
        ),
        findsOneWidget,
      );
      // The chip counts the two that count, not the optional one.
      expect(
        _in(_chip('s2'), find.text('1 of 2 demonstrated')),
        findsOneWidget,
      );
      // No advice, no retry: nothing in the list to press.
      for (final type in [ButtonStyleButton, IconButton, InkWell]) {
        expect(
          find.descendant(of: _panel, matching: find.byType(type)),
          findsNothing,
        );
      }

      await tester.tap(_chip('s1'));
      await tester.pumpAndSettle();
      expect(find.text('Je kan met print() tekst tonen.'), findsOneWidget);
      expect(find.text('Je kan invoer omzetten naar een getal.'), findsNothing);

      await tester.tap(_chip('s1'));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
    });

    testWidgets('in Dutch: "x van y aangetoond", "aangetoond" and "nog niet '
        'aangetoond"', (tester) async {
      await tester.pumpWidget(
        _card(
          {'s2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp)},
          stamps: _stamps(['s2/lo-var']),
          locale: const Locale('nl'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_in(_chip('s2'), find.text('1 van 2 aangetoond')), findsOneWidget);
      await tester.tap(_chip('s2'));
      await tester.pumpAndSettle();
      expect(find.text('aangetoond'), findsOneWidget);
      expect(find.text('nog niet aangetoond'), findsOneWidget);
      expect(find.text('nog niet aangetoond · optioneel'), findsOneWidget);
    });

    testWidgets('a statement with an English translation shows in English, '
        'one without in Dutch, without a notice', (tester) async {
      final store = InMemoryCosmos.partitioned('language', [
        Translation.objective(
          language: 'en',
          subgoalId: 's2',
          loId: 'lo-var',
          statement: 'You can keep a value in a variable.',
          sourceHash: objectiveSourceHash(_vars.objectives[1]),
        ).toMap(),
      ]);
      await tester.pumpWidget(
        _card(
          {'s2': Progress(goalID: 's2', progress: 0.5)},
          stamps: _stamps(['s2/lo-var']),
          translations: TranslationService(container: store.container),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_chip('s2'));
      await tester.pumpAndSettle();

      expect(find.text('You can keep a value in a variable.'), findsOneWidget);
      expect(
        find.text('Je kan een waarde in een variabele bewaren.'),
        findsNothing,
      );
      expect(
        find.text('Je kan invoer omzetten naar een getal.'),
        findsOneWidget,
      );
      expect(find.textContaining('Dutch'), findsNothing);
    });

    testWidgets('while the stamps are not known the list shows the '
        'sentences without a status', (tester) async {
      await tester.pumpWidget(
        _card({'s2': Progress(goalID: 's2', progress: 0.5)}),
      );
      await tester.pumpAndSettle();
      await tester.tap(_chip('s2'));
      await tester.pumpAndSettle();

      expect(
        find.text('Je kan een waarde in een variabele bewaren.'),
        findsOneWidget,
      );
      expect(find.textContaining('demonstrated'), findsNothing);
      expect(find.text('optional'), findsOneWidget);
    });

    testWidgets('a subgoal without learning objectives is not a button', (
      tester,
    ) async {
      final bare = Goal(id: 's3', title: 'Bare', parentId: 'r', order: 3);
      await tester.pumpWidget(
        _card(
          {'s3': Progress(goalID: 's3', progress: 0.5)},
          children: [bare],
          stamps: _stamps(const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<LeerpadChildChip>(_chip('s3')).onTap, isNull);
      expect(_bar(tester, _chip('s3')), closeTo(0.5, 1e-9));
      expect(find.textContaining('demonstrated'), findsNothing);
    });
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
