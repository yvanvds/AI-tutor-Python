// Issue #85 — planning for the scoped Replace import. The plan decides which
// existing set (root goal + subtree) each root entry in the file replaces,
// and which ids inside that set get deleted. The one thing it must never do
// is put another set's goals in a `removedIds` — that is exactly the bug the
// global Replace had.

import 'package:ai_tutor_python/features/goals/goal_import_plan.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter_test/flutter_test.dart';

Goal _goal(String id, String title, {String? parentId}) =>
    Goal(id: id, title: title, parentId: parentId, order: 1000);

Map<String, dynamic> _entry(
  String? id,
  String title,
  List<(String, String)> subgoals,
) => {
  'goal': {'id': id, 'title': title},
  'subgoals': [
    for (final (sid, stitle) in subgoals) {'id': sid, 'title': stitle},
  ],
};

void main() {
  // Two sets: A (rA > a1, a2) and B (rB > b1). B must never be touched by a
  // plan that targets A.
  final existing = [
    _goal('rA', 'Basics'),
    _goal('a1', 'Print', parentId: 'rA'),
    _goal('a2', 'Variables', parentId: 'rA'),
    _goal('rB', 'Extra'),
    _goal('b1', 'Lists', parentId: 'rB'),
  ];

  group('subtreeIds', () {
    test('collects the root and every descendant, depth included', () {
      final deep = [...existing, _goal('a1x', 'Nested', parentId: 'a1')];
      expect(subtreeIds(deep, 'rA'), {'rA', 'a1', 'a2', 'a1x'});
    });

    test('never crosses into another root', () {
      expect(subtreeIds(existing, 'rB'), {'rB', 'b1'});
    });
  });

  group('entryIds', () {
    test('collects root and subgoal ids, skipping missing ones', () {
      final entry = _entry('rA', 'Basics', [('a1', 'Print')]);
      (entry['subgoals'] as List).add({'id': '', 'title': 'no id'});
      expect(entryIds(entry), {'rA', 'a1'});
    });
  });

  group('buildReplacePlan', () {
    test('matches by root id and removes only within that set', () {
      final plan = buildReplacePlan(existing, [
        _entry('rA', 'Basics v2', [('a1', 'Print'), ('a3', 'Loops')]),
      ]);

      expect(plan.unmatched, isEmpty);
      expect(plan.resolved, hasLength(1));
      final target = plan.resolved.single;
      expect(target.existingRoot!.id, 'rA');
      // a2 is dropped by the file; B's goals are not touched.
      expect(target.removedIds, {'a2'});
    });

    test('falls back to a unique title match when the ids were regenerated '
        'and deletes the whole old subtree', () {
      final plan = buildReplacePlan(existing, [
        _entry('rA-new', 'Basics', [('a1-new', 'Print')]),
      ]);

      expect(plan.unmatched, isEmpty);
      final target = plan.resolved.single;
      expect(target.existingRoot!.id, 'rA');
      expect(target.removedIds, {'rA', 'a1', 'a2'});
    });

    test('an ambiguous title match is not guessed at', () {
      final twins = [...existing, _goal('rA2', 'Basics')];
      final plan = buildReplacePlan(twins, [
        _entry('unknown', 'Basics', const []),
      ]);
      expect(plan.resolved, isEmpty);
      expect(plan.unmatched, hasLength(1));
    });

    test('a root matching nothing lands in unmatched', () {
      final plan = buildReplacePlan(existing, [
        _entry('rX', 'Fresh', const []),
      ]);
      expect(plan.resolved, isEmpty);
      expect(plan.unmatched, hasLength(1));
    });

    test('an existing root is claimed by at most one entry', () {
      final plan = buildReplacePlan(existing, [
        _entry('rA', 'Basics', const []),
        // Same title as rA, but rA is already claimed by the id match above.
        _entry('other', 'Basics', const []),
      ]);
      expect(plan.resolved, hasLength(1));
      expect(plan.unmatched, hasLength(1));
    });

    test('multiple entries resolve independently, never overlapping sets', () {
      final plan = buildReplacePlan(existing, [
        _entry('rA', 'Basics', [('a1', 'Print')]),
        _entry('rB', 'Extra', const []),
      ]);
      expect(plan.unmatched, isEmpty);
      final byRoot = {
        for (final t in plan.resolved) t.existingRoot!.id: t.removedIds,
      };
      expect(byRoot['rA'], {'a2'});
      expect(byRoot['rB'], {'b1'});
    });
  });

  group('resolveTarget', () {
    test('a manually chosen set is removed in full when the file shares no '
        'ids with it', () {
      final entry = _entry('rX', 'Fresh', [('y1', 'Intro')]);
      final target = resolveTarget(existing, entry, existing[3]); // rB
      expect(target.existingRoot!.id, 'rB');
      expect(target.removedIds, {'rB', 'b1'});
    });
  });
}
