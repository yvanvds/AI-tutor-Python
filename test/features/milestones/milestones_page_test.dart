// The Mijlpalen page, at the two points #148 touched it.
//
// 1. The empty-title hole. The editor is a `ListView` inside the `Form`,
//    and Save sits at the very bottom of it. With a real curriculum the
//    teacher has to scroll to reach Save — which unmounts the title field
//    at the top, and an unmounted `FormField` has deregistered from the
//    `Form`, so `validate()` never runs its "give the milestone a title"
//    validator. That is how a milestone with `title: ""` reached Cosmos,
//    and an untitled milestone is what made the grade-proposal milestone
//    dropdown render blank. Saving now checks the controller, which is
//    still there whether or not its field is on screen.
//
// 2. The nudge: a milestone whose report date has gone by while no report
//    has been generated for it is flagged in the list.

import 'package:ai_tutor_python/features/milestones/milestones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

Map<String, dynamic> _goal(
  String id,
  String title, {
  String? parentId,
  int order = 0,
  List<Map<String, dynamic>> objectives = const [],
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': false,
  'teachingTips': <String>[],
  'allowChains': false,
  'objectives': objectives,
  'moduleId': 'python-basics',
};

/// A curriculum long enough that Save is below the fold, like the real one.
List<Map<String, dynamic>> _longCurriculum() => [
  _goal('r1', 'Basics'),
  for (var i = 0; i < 25; i++)
    _goal(
      's$i',
      'Subgoal $i',
      parentId: 'r1',
      order: i * 100,
      objectives: [
        {
          'id': 'lo$i',
          'statement': 'Objective $i',
          'kind': 'apply',
          'weight': 1.0,
          'optional': false,
        },
      ],
    ),
];

Map<String, dynamic> _milestoneDoc({
  required String id,
  required String title,
  required DateTime dueAt,
}) => {
  'id': id,
  'type': 'milestone',
  'title': title,
  'periodStart': dueAt.subtract(const Duration(days: 60)).toIso8601String(),
  'dueAt': dueAt.toIso8601String(),
  'expectedDifficulty': 'medium',
  'subgoalIds': ['s0'],
  'coreLoKeys': ['s0/lo0'],
};

Map<String, dynamic> _proposalDoc(String uid, String milestoneId) => {
  'id': '${uid}_$milestoneId',
  'type': 'grade_proposal',
  'uid': uid,
  'milestoneId': milestoneId,
  'formulaVersion': '1.0.7',
  'computedAt': DateTime.now().toUtc().toIso8601String(),
  'proposal': 70,
};

void main() {
  Future<void> mount(
    WidgetTester tester, {
    List<Map<String, dynamic>> goals = const [],
    List<Map<String, dynamic>> milestones = const [],
    List<Map<String, dynamic>> proposals = const [],
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    InMemoryCosmosClient({
      'goals': InMemoryCosmos(goals),
      'milestones': InMemoryCosmos(milestones),
      'grade_proposals': InMemoryCosmos(proposals),
    }).install();
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(const Scaffold(body: MilestonesPage())),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Jumps the editor's own list to the bottom, the way a teacher reaching
  /// the Save button does.
  Future<void> scrollEditorToBottom(WidgetTester tester) async {
    final editor = find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 30; i++) {
      final position = tester.state<ScrollableState>(editor).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
  }

  testWidgets('an untitled milestone is refused even when the title field '
      'has scrolled out of the editor', (tester) async {
    final store = InMemoryCosmos();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    InMemoryCosmosClient({
      'goals': InMemoryCosmos(_longCurriculum()),
      'milestones': store,
      'grade_proposals': InMemoryCosmos(),
    }).install();
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(const Scaffold(body: MilestonesPage())),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('New milestone'));
    await tester.pump();
    // The teacher fills the report date and picks a subgoal, but never
    // types a title.
    await tester.enterText(
      find.byKey(const Key('milestone-due-at')),
      formatIsoDate(DateTime.now().add(const Duration(days: 30))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('milestone-subgoal-s0')));
    await tester.pump();

    await scrollEditorToBottom(tester);
    expect(
      find.byKey(const Key('milestone-title')),
      findsNothing,
      reason: 'the title field has been unmounted by the list',
    );

    await tester.tap(find.byKey(const Key('milestone-save')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(store.docs, isEmpty, reason: 'nothing untitled reached Cosmos');
    expect(find.byKey(const Key('milestone-save-error')), findsOneWidget);
    expect(find.text('Give the milestone a title.'), findsOneWidget);
  });

  testWidgets('a titled milestone still saves from the bottom of the list', (
    tester,
  ) async {
    final store = InMemoryCosmos();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    InMemoryCosmosClient({
      'goals': InMemoryCosmos(_longCurriculum()),
      'milestones': store,
      'grade_proposals': InMemoryCosmos(),
    }).install();
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(const Scaffold(body: MilestonesPage())),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('New milestone'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('milestone-title')),
      'Rapport 1',
    );
    await tester.enterText(
      find.byKey(const Key('milestone-due-at')),
      formatIsoDate(DateTime.now().add(const Duration(days: 30))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('milestone-subgoal-s0')));
    await tester.pump();

    await scrollEditorToBottom(tester);
    await tester.tap(find.byKey(const Key('milestone-save')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(store.docs.values.single['title'], 'Rapport 1');
    expect(find.byKey(const Key('milestone-save-error')), findsNothing);
  });

  testWidgets('an overdue milestone with no reports is flagged; one with a '
      'report, and one still ahead, are not', (tester) async {
    final now = DateTime.now();
    await mount(
      tester,
      goals: _longCurriculum(),
      milestones: [
        _milestoneDoc(
          id: 'overdue',
          title: 'Rapport 1',
          dueAt: now.subtract(const Duration(days: 3)),
        ),
        _milestoneDoc(
          id: 'reported',
          title: 'Rapport 2',
          dueAt: now.subtract(const Duration(days: 2)),
        ),
        _milestoneDoc(
          id: 'ahead',
          title: 'Rapport 3',
          dueAt: now.add(const Duration(days: 30)),
        ),
      ],
      proposals: [_proposalDoc('u1', 'reported')],
    );

    expect(find.byKey(const Key('milestone-overdue-overdue')), findsOneWidget);
    expect(find.byKey(const Key('milestone-overdue-reported')), findsNothing);
    expect(find.byKey(const Key('milestone-overdue-ahead')), findsNothing);
  });
}
