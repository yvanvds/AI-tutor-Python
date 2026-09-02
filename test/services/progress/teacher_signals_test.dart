// Unit tests for the pure teacher-overview helpers (#89): overall progress
// of the *active* root must average over every non-optional subgoal defined
// under that root — unstarted subgoals count as 0 — instead of averaging
// only the subgoals that happen to have a progress record.

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter_test/flutter_test.dart';

Goal _goal(String id, {String? parentId, bool optional = false}) =>
    Goal(id: id, title: id, parentId: parentId, order: 0, optional: optional);

Progress _p(String goalId, double value, {String at = '2026-05-01T10:00:00Z'}) {
  return Progress(
    goalID: goalId,
    progress: value,
    updatedAt: DateTime.parse(at),
    lastSessionAt: DateTime.parse(at),
  );
}

void main() {
  // One root with 8 non-optional subgoals, mirroring the shape from the
  // issue report.
  final goals = <Goal>[
    _goal('r1'),
    for (var i = 1; i <= 8; i++) _goal('s$i', parentId: 'r1'),
  ];
  final goalById = {for (final g in goals) g.id: g};
  final parentByChild = {for (final g in goals) g.id: g.parentId};

  group('activeRootProgress', () {
    test('1 of 8 subgoals finished shows 1/8, not 100%', () {
      final value = activeRootProgress(
        progress: [_p('s1', 1.0)],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(value, closeTo(1 / 8, 1e-9));
    });

    test('records at 1.0 and 0.0 with 6 unstarted average to 1/8, not 50%', () {
      final value = activeRootProgress(
        progress: [_p('s1', 1.0), _p('s2', 0.0)],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(value, closeTo(1 / 8, 1e-9));
    });

    test('all subgoals finished shows 100%', () {
      final value = activeRootProgress(
        progress: [for (var i = 1; i <= 8; i++) _p('s$i', 1.0)],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(value, closeTo(1.0, 1e-9));
    });

    test('optional subgoals are excluded from both sides of the average', () {
      final withOptional = <Goal>[
        _goal('r1'),
        _goal('s1', parentId: 'r1'),
        _goal('s2', parentId: 'r1'),
        _goal('opt', parentId: 'r1', optional: true),
      ];
      final value = activeRootProgress(
        progress: [_p('s1', 1.0), _p('opt', 1.0)],
        goalById: {for (final g in withOptional) g.id: g},
        parentByChild: {for (final g in withOptional) g.id: g.parentId},
      );
      // 1.0 over {s1, s2}; the finished optional neither adds nor divides.
      expect(value, closeTo(0.5, 1e-9));
    });

    test('no progress at all shows 0', () {
      final value = activeRootProgress(
        progress: const [],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(value, 0.0);
    });

    test('uses the active root only, not an average over touched roots', () {
      final twoRoots = <Goal>[
        _goal('r1'),
        _goal('s1', parentId: 'r1'),
        _goal('s2', parentId: 'r1'),
        _goal('r2'),
        _goal('t1', parentId: 'r2'),
        _goal('t2', parentId: 'r2'),
      ];
      final value = activeRootProgress(
        progress: [
          _p('s1', 1.0, at: '2026-05-01T10:00:00Z'),
          _p('t1', 0.5, at: '2026-05-02T10:00:00Z'), // most recent → r2
        ],
        goalById: {for (final g in twoRoots) g.id: g},
        parentByChild: {for (final g in twoRoots) g.id: g.parentId},
      );
      // 0.5 over r2's {t1, t2} — r1's finished subgoal is another story.
      expect(value, closeTo(0.25, 1e-9));
    });

    test('a derived record on the root itself resolves to that root', () {
      final value = activeRootProgress(
        progress: [
          _p('s1', 1.0, at: '2026-05-01T10:00:00Z'),
          _p('r1', 0.125, at: '2026-05-02T10:00:00Z'),
        ],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      // The root cache doc picks root r1; the average still comes from the
      // subgoal records: 1.0 over 8.
      expect(value, closeTo(1 / 8, 1e-9));
    });

    test('an active record on an unknown goal shows 0 (matches the em-dash '
        'in Current goal)', () {
      final value = activeRootProgress(
        progress: [_p('deleted-goal', 1.0)],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(value, 0.0);
    });

    test('a root without non-optional subgoals shows 0', () {
      final bare = <Goal>[
        _goal('r1'),
        _goal('opt', parentId: 'r1', optional: true),
      ];
      final value = activeRootProgress(
        progress: [_p('opt', 1.0)],
        goalById: {for (final g in bare) g.id: g},
        parentByChild: {for (final g in bare) g.id: g.parentId},
      );
      expect(value, 0.0);
    });
  });

  group('activeGoalTitles', () {
    // Titled goals so root and subgoal lines are distinguishable.
    final titled = <Goal>[
      Goal(id: 'r1', title: 'Basics', parentId: null, order: 0),
      Goal(id: 's1', title: 'Print', parentId: 'r1', order: 0),
      Goal(id: 's2', title: 'Variables', parentId: 'r1', order: 0),
    ];
    final titledById = {for (final g in titled) g.id: g};
    final titledParents = {for (final g in titled) g.id: g.parentId};

    test('active subgoal yields root title plus subgoal title', () {
      final titles = activeGoalTitles(
        progress: [_p('s2', 0.5)],
        goalById: titledById,
        parentByChild: titledParents,
      );
      expect(titles, (rootTitle: 'Basics', subgoalTitle: 'Variables'));
    });

    test('the most recently active subgoal wins', () {
      final titles = activeGoalTitles(
        progress: [
          _p('s1', 1.0, at: '2026-05-01T10:00:00Z'),
          _p('s2', 0.5, at: '2026-05-02T10:00:00Z'),
        ],
        goalById: titledById,
        parentByChild: titledParents,
      );
      expect(titles, (rootTitle: 'Basics', subgoalTitle: 'Variables'));
    });

    test('an active record on the root itself yields one line', () {
      final titles = activeGoalTitles(
        progress: [_p('r1', 0.5)],
        goalById: titledById,
        parentByChild: titledParents,
      );
      expect(titles, (rootTitle: 'Basics', subgoalTitle: null));
    });

    test('no progress yields null (the em-dash case)', () {
      final titles = activeGoalTitles(
        progress: const [],
        goalById: titledById,
        parentByChild: titledParents,
      );
      expect(titles, isNull);
    });

    test('an active record on an unknown goal yields null', () {
      final titles = activeGoalTitles(
        progress: [_p('deleted-goal', 1.0)],
        goalById: titledById,
        parentByChild: titledParents,
      );
      expect(titles, isNull);
    });

    test('a subgoal whose parent is missing falls back to its own title '
        'on one line', () {
      final orphan = Goal(
        id: 'o1',
        title: 'Orphan',
        parentId: 'ghost',
        order: 0,
      );
      final titles = activeGoalTitles(
        progress: [_p('o1', 0.5)],
        goalById: {'o1': orphan},
        parentByChild: {'o1': 'ghost'},
      );
      expect(titles, (rootTitle: 'Orphan', subgoalTitle: null));
    });

    test('a multi-level leaf reports the top root plus its own title', () {
      final deep = <Goal>[
        Goal(id: 'r1', title: 'Basics', parentId: null, order: 0),
        Goal(id: 'mid', title: 'Middle', parentId: 'r1', order: 0),
        Goal(id: 'leaf', title: 'Leaf', parentId: 'mid', order: 0),
      ];
      final titles = activeGoalTitles(
        progress: [_p('leaf', 0.5)],
        goalById: {for (final g in deep) g.id: g},
        parentByChild: {for (final g in deep) g.id: g.parentId},
      );
      expect(titles, (rootTitle: 'Basics', subgoalTitle: 'Leaf'));
    });
  });

  group('activeRootId', () {
    test('walks multi-level parents up to the root', () {
      final deep = <Goal>[
        _goal('r1'),
        _goal('mid', parentId: 'r1'),
        _goal('leaf', parentId: 'mid'),
      ];
      final id = activeRootId(
        progress: [_p('leaf', 0.5)],
        parentByChild: {for (final g in deep) g.id: g.parentId},
      );
      expect(id, 'r1');
    });

    test('returns null on a parent cycle instead of hanging', () {
      final id = activeRootId(
        progress: [_p('a', 0.5)],
        parentByChild: {'a': 'b', 'b': 'a'},
      );
      expect(id, isNull);
    });
  });
}
