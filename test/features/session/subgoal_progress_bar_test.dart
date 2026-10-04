// Issue #230 — the subgoal bar in the objective banner is one segment per
// non-optional LO, each empty, half or full, as the conductor publishes
// them; a tooltip and the screen-reader label say it in words in the app
// language. The 2px ambient line at the top follows the same share. Until
// the conductor has published the active subgoal's segments the bar is the
// cached share, as before.
//
// The conductor's side — which state each LO gets, and the hold over a
// session — is in test/services/tutor/lo_display_test.dart and
// conductor_test.dart; the real app end to end in
// integration_test/flows/subgoal_segments.dart.

import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/features/session/widgets/subgoal_progress_bar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
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

final _root = Goal(id: 'r1', title: 'Basis', order: 0);
final _printen = Goal(id: 's1', title: 'Printen', parentId: 'r1', order: 1);

class _PresetSelection extends GoalSelectionNotifier {
  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: _root, selectedChild: _printen);
}

SubgoalLoDisplay _bar(List<LoDisplayState> states, {String subgoalId = 's1'}) =>
    SubgoalLoDisplay(
      subgoalId: subgoalId,
      los: [
        for (var i = 0; i < states.length; i++)
          LoDisplayEntry(loId: 'lo-$i', state: states[i]),
      ],
    );

const _full = LoDisplayState.full;
const _half = LoDisplayState.half;
const _empty = LoDisplayState.empty;

void main() {
  Future<void> mount(
    WidgetTester tester, {
    SubgoalLoDisplay? display,
    Locale locale = const Locale('en'),
    double cached = 0.25,
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
          const Scaffold(
            body: Column(children: [AmbientProgress(), ObjectiveBanner()]),
          ),
          locale: locale,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<LoDisplayState> segments(WidgetTester tester) => [
    for (final s in tester.widgetList<LoSegment>(find.byType(LoSegment)))
      s.state,
  ];

  /// The filled part of [segment] as a share of its width.
  double filled(WidgetTester tester, Finder segment) {
    final fill = find.descendant(
      of: find.descendant(
        of: segment,
        matching: find.byType(FractionallySizedBox),
      ),
      matching: find.byType(Container),
    );
    return tester.getSize(fill).width / tester.getSize(segment).width;
  }

  Color fillColor(WidgetTester tester, Finder segment) {
    final fill = find.descendant(
      of: find.descendant(
        of: segment,
        matching: find.byType(FractionallySizedBox),
      ),
      matching: find.byType(Container),
    );
    return (tester.widget<Container>(fill).color)!;
  }

  double ambientShare(WidgetTester tester) => tester
      .widget<AnimatedFractionallySizedBox>(
        find.descendant(
          of: find.byType(AmbientProgress),
          matching: find.byType(AnimatedFractionallySizedBox),
        ),
      )
      .widthFactor!;

  testWidgets('one segment per LO, filled empty / half / full in order, and '
      'the ambient line at the share they fill', (tester) async {
    await mount(tester, display: _bar([_full, _half, _empty, _empty]));

    expect(segments(tester), [_full, _half, _empty, _empty]);
    final all = find.byType(LoSegment);
    expect(filled(tester, all.at(0)), closeTo(1.0, 0.01));
    expect(filled(tester, all.at(1)), closeTo(0.5, 0.01));
    expect(filled(tester, all.at(2)), closeTo(0.0, 0.01));
    // Segments side by side, the same width.
    expect(
      tester.getSize(all.at(0)).width,
      closeTo(tester.getSize(all.at(3)).width, 0.01),
    );
    expect(
      tester.getTopLeft(all.at(1)).dx,
      greaterThan(tester.getTopRight(all.at(0)).dx),
    );
    // Not the cached share (0.25): 1.5 of 4 segments.
    expect(ambientShare(tester), closeTo(1.5 / 4, 1e-9));
  });

  testWidgets('a tooltip and the screen-reader label say it in English', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, display: _bar([_full, _half, _empty]));

    const label = '1 part mastered, 1 almost, 1 still to do';
    expect(find.byTooltip(label), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('…and in Dutch, plural included', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(
      tester,
      locale: const Locale('nl'),
      display: _bar([_full, _full, _half, _empty, _empty]),
    );

    const label = '2 onderdelen beheerst, 1 bijna, 2 nog te doen';
    expect(find.byTooltip(label), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hovering the bar shows the tooltip', (tester) async {
    await mount(tester, display: _bar([_half, _empty]));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SubgoalProgressBar)));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      find.text('0 parts mastered, 1 almost, 1 still to do'),
      findsOneWidget,
    );
  });

  testWidgets('every segment full: the bar takes the "finished" colour', (
    tester,
  ) async {
    await mount(tester, display: _bar([_full, _full]));
    final all = find.byType(LoSegment);
    expect(fillColor(tester, all.at(0)), AppColors.accent2);
    expect(fillColor(tester, all.at(1)), AppColors.accent2);

    await mount(tester, display: _bar([_full, _half]));
    expect(fillColor(tester, find.byType(LoSegment).at(0)), AppColors.accent);
  });

  testWidgets('segments of another subgoal, or none yet: the plain bar of '
      'the cached share', (tester) async {
    await mount(tester, display: _bar([_full, _full], subgoalId: 's2'));

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
