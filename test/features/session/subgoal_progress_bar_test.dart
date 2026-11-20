// Issues #230 and #325 — the subgoal bar in the objective banner is one
// segment per non-optional LO, as the conductor publishes them. Each shows
// the right answers its LO still needs and fills along with that number,
// carries a tick when the LO is demonstrated, and is framed when the
// exercise on screen is about it. Hovering or tapping a segment opens its
// popup — the "Je kan …" sentence, the state, why the number went up — and
// the bar's own tooltip and screen-reader label give the whole subgoal, in
// the app language. The 2px ambient line at the top follows the share the
// segments fill. Until the conductor has published the active subgoal's
// segments the bar is the cached share, as before.
//
// The conductor's side — what each LO counts, the readings over a session,
// the marker — is in test/services/tutor/lo_display_test.dart and
// conductor_test.dart; the real app end to end in
// integration_test/flows/subgoal_segments.dart.

import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/features/session/widgets/subgoal_progress_bar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/tutor/lo_display.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

const _statements = [
  'Je kan een zin printen.',
  'Je kan meerdere waarden tegelijk printen.',
  'Je kan het scheidingsteken kiezen.',
  'Je kan een lege regel printen.',
  'Je kan tekst en getallen samen printen.',
  'Je kan een regel laten eindigen zonder overgang.',
  'Je kan een f-string printen.',
  'Je kan aanhalingstekens in tekst printen.',
];

final _root = Goal(id: 'r1', title: 'Basis', order: 0);
final _printen = Goal(
  id: 's1',
  title: 'Printen',
  parentId: 'r1',
  order: 1,
  objectives: [
    for (var i = 0; i < _statements.length; i++)
      LearningObjective(
        id: 'lo-$i',
        statement: _statements[i],
        kind: LoKind.apply,
      ),
  ],
);

class _PresetSelection extends GoalSelectionNotifier {
  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: _root, selectedChild: _printen);
}

/// A bar of the given right answers to go, on medium (a new LO needs 3).
SubgoalLoDisplay _bar(
  List<int> toGo, {
  String subgoalId = 's1',
  Set<int> demonstrated = const {},
  Map<int, LoDisplayRise> rose = const {},
  int? current,
}) => SubgoalLoDisplay(
  subgoalId: subgoalId,
  los: [
    for (var i = 0; i < toGo.length; i++)
      LoDisplayEntry(
        loId: 'lo-$i',
        toGo: toGo[i],
        newLoToGo: 3,
        demonstrated: demonstrated.contains(i),
        rose: rose[i],
      ),
  ],
  currentLoId: current == null ? null : 'lo-$current',
);

void main() {
  Future<void> mount(
    WidgetTester tester, {
    SubgoalLoDisplay? display,
    Locale locale = const Locale('en'),
    double cached = 0.25,
    double width = 800,
  }) async {
    final progress = InMemoryCosmos([
      Progress(goalID: 's1', progress: cached).toMap(uid: 'u1'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope on every mount: a test that mounts twice gets the
        // second set of overrides.
        key: UniqueKey(),
        overrides: [
          appLocaleProvider.overrideWithValue(locale),
          translationServiceProvider.overrideWithValue(
            TranslationService(
              container: InMemoryCosmos.partitioned('language').container,
            ),
          ),
          goalSelectionProvider.overrideWith(_PresetSelection.new),
          progressServiceProvider.overrideWithValue(
            ProgressService(container: progress.container, getUid: () => 'u1'),
          ),
          subgoalLoDisplayProvider.overrideWith((_) => display),
        ],
        child: localizedTestApp(
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const Column(
                  children: [AmbientProgress(), ObjectiveBanner()],
                ),
              ),
            ),
          ),
          locale: locale,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder segment(int i) => find.byKey(ValueKey('lo-segment-lo-$i'));

  /// The share of [segment] the fill is heading for.
  double fillOf(WidgetTester tester, Finder segment) => tester
      .widget<TweenAnimationBuilder<double>>(
        find.descendant(
          of: segment,
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
      )
      .tween
      .end!;

  /// The number in [segment], or `null` when it shows none. It is drawn
  /// twice — over the empty part and over the fill — so it reads on both.
  String? numberIn(WidgetTester tester, Finder segment) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: segment, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .toSet();
    expect(texts.length, lessThanOrEqualTo(1));
    return texts.isEmpty ? null : texts.single;
  }

  bool tickIn(Finder segment) => find
      .descendant(of: segment, matching: find.byIcon(Icons.check_rounded))
      .evaluate()
      .isNotEmpty;

  bool framed(WidgetTester tester, Finder segment) =>
      tester.widget<LoSegment>(segment).current &&
      tester
              .widget<Container>(
                find
                    .descendant(of: segment, matching: find.byType(Container))
                    .first,
              )
              .foregroundDecoration !=
          null;

  double ambientShare(WidgetTester tester) => tester
      .widget<AnimatedFractionallySizedBox>(
        find.descendant(
          of: find.byType(AmbientProgress),
          matching: find.byType(AnimatedFractionallySizedBox),
        ),
      )
      .widthFactor!;

  testWidgets('one segment per LO in order, each with the right answers to '
      'go, filled from where a new LO starts; the ambient line at the share '
      'they fill', (tester) async {
    await mount(tester, display: _bar([0, 1, 2, 3, 5]));

    expect(find.byType(LoSegment), findsNWidgets(5));
    expect(
      [for (var i = 0; i < 5; i++) numberIn(tester, segment(i))],
      [null, '1', '2', '3', '5'],
    );
    expect(fillOf(tester, segment(0)), 1.0);
    expect(fillOf(tester, segment(1)), closeTo(2 / 3, 1e-9));
    expect(fillOf(tester, segment(2)), closeTo(1 / 3, 1e-9));
    expect(fillOf(tester, segment(3)), 0.0);
    expect(fillOf(tester, segment(4)), 0.0);
    // Segments side by side, the same width.
    expect(
      tester.getSize(segment(0)).width,
      closeTo(tester.getSize(segment(4)).width, 0.01),
    );
    expect(
      tester.getTopLeft(segment(1)).dx,
      greaterThan(tester.getTopRight(segment(0)).dx),
    );
    // Not the cached share (0.25): (1 + 2/3 + 1/3) of 5 segments.
    expect(ambientShare(tester), closeTo(2 / 5, 1e-9));
  });

  testWidgets('a demonstrated LO carries a tick, also when its fill dropped; '
      'the segment of the exercise on screen is framed', (tester) async {
    await mount(
      tester,
      display: _bar([0, 2, 3], demonstrated: {0, 1}, current: 2),
    );

    expect(tickIn(segment(0)), isTrue);
    expect(tickIn(segment(1)), isTrue);
    expect(numberIn(tester, segment(1)), '2');
    expect(tickIn(segment(2)), isFalse);

    expect(framed(tester, segment(2)), isTrue);
    expect(framed(tester, segment(0)), isFalse);
    expect(framed(tester, segment(1)), isFalse);
  });

  testWidgets('each segment has its own popup and screen-reader label: the '
      'sentence, the state, why it went up, and the exercise on screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(
      tester,
      display: _bar(
        [0, 1, 2, 4],
        demonstrated: {0, 2},
        rose: {2: LoDisplayRise.notRight, 3: LoDisplayRise.otherQuestion},
        current: 1,
      ),
    );

    // The app has no English statement yet: the Dutch one shows.
    final popups = [
      '${_statements[0]}\nMastered · demonstrated',
      '${_statements[1]}\n1 more right answer\n'
          'Your current exercise is about this.',
      '${_statements[2]}\n2 more right answers · demonstrated\n'
          'Went up after an answer that was not right.',
      '${_statements[3]}\n4 more right answers\n'
          'Went up after a mistake on this in a question about something '
          'else.',
    ];
    for (final popup in popups) {
      expect(find.byTooltip(popup), findsOneWidget, reason: popup);
      expect(find.bySemanticsLabel(popup), findsOneWidget, reason: popup);
    }
    semantics.dispose();
  });

  testWidgets('…and in Dutch, with a lower level as the reason', (
    tester,
  ) async {
    await mount(
      tester,
      locale: const Locale('nl'),
      display: _bar([1, 3], rose: {1: LoDisplayRise.lowerLevel}, current: 0),
    );

    expect(
      find.byTooltip(
        '${_statements[0]}\nNog 1 juist antwoord\n'
        'Je huidige oefening gaat hierover.',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        '${_statements[1]}\nNog 3 juiste antwoorden\n'
        'Gestegen: je vragen zijn nu makkelijker, en daar telt een juist '
        'antwoord minder.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the bar\'s tooltip and screen-reader label give the whole '
      'subgoal, in English and in Dutch', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, display: _bar([0, 1, 2]));
    const en = '1 of 3 parts mastered, 3 more right answers to go';
    expect(find.byTooltip(en), findsOneWidget);
    expect(find.bySemanticsLabel(en), findsOneWidget);

    await mount(tester, locale: const Locale('nl'), display: _bar([0, 0, 1]));
    const nl = '2 van 3 onderdelen beheerst, nog 1 juist antwoord';
    expect(find.byTooltip(nl), findsOneWidget);
    expect(find.bySemanticsLabel(nl), findsOneWidget);

    await mount(tester, display: _bar([0, 0]));
    expect(find.byTooltip('2 of 2 parts mastered'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hovering a segment opens its popup; hovering between the '
      'segments the bar\'s', (tester) async {
    await mount(tester, display: _bar([1, 3]));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(segment(1)));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.text('${_statements[1]}\n3 more right answers'),
      findsOneWidget,
    );
    expect(
      find.text('0 of 2 parts mastered, 4 more right answers to go'),
      findsNothing,
    );

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // Between the two segments.
    final gap = Offset(
      (tester.getTopRight(segment(0)).dx + tester.getTopLeft(segment(1)).dx) /
          2,
      tester.getCenter(segment(0)).dy,
    );
    await gesture.moveTo(gap);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.text('0 of 2 parts mastered, 4 more right answers to go'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a segment opens its popup', (tester) async {
    await mount(tester, display: _bar([2, 3]));

    await tester.tap(segment(0));
    await tester.pumpAndSettle();
    expect(
      find.text('${_statements[0]}\n2 more right answers'),
      findsOneWidget,
    );
  });

  testWidgets('every segment mastered: the bar takes the "finished" colour', (
    tester,
  ) async {
    Color fillColor(Finder segment) => tester
        .widgetList<ColoredBox>(
          find.descendant(of: segment, matching: find.byType(ColoredBox)),
        )
        .last
        .color;

    await mount(tester, display: _bar([0, 0]));
    expect(fillColor(segment(0)), AppColors.accent2);
    expect(fillColor(segment(1)), AppColors.accent2);

    await mount(tester, display: _bar([0, 1]));
    expect(fillColor(segment(0)), AppColors.accent);
  });

  testWidgets('a narrow banner with many LOs: every segment keeps its '
      'number, without overflow', (tester) async {
    await mount(
      tester,
      width: 320,
      display: _bar(
        [12, 3, 2, 1, 0, 5, 8, 2],
        demonstrated: {1, 4},
        current: 0,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LoSegment), findsNWidgets(8));
    expect(numberIn(tester, segment(0)), '12');
    expect(numberIn(tester, segment(6)), '8');
    for (var i = 0; i < 8; i++) {
      expect(tester.getSize(segment(i)).width, greaterThan(20));
    }
  });

  testWidgets('segments of another subgoal, or none yet: the plain bar of '
      'the cached share', (tester) async {
    await mount(tester, display: _bar([0, 0], subgoalId: 's2'));

    expect(find.byType(LoSegment), findsNothing);
    expect(find.byType(SubgoalProgressBar), findsOneWidget);
    expect(ambientShare(tester), closeTo(0.25, 1e-9));
    final plain = find.descendant(
      of: find.byType(SubgoalProgressBar),
      matching: find.byType(AnimatedFractionallySizedBox),
    );
    expect(
      tester.widget<AnimatedFractionallySizedBox>(plain).widthFactor,
      closeTo(0.25, 1e-9),
    );

    await mount(tester);
    expect(find.byType(LoSegment), findsNothing);
    expect(ambientShare(tester), closeTo(0.25, 1e-9));
  });
}
