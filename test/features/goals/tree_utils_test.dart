// 1C.1 — Tests the three pure functions in `tree_utils.dart`. The
// drag-and-drop reparent code uses these to gate drops; a goal becoming
// its own ancestor is unrecoverable in the UI, so cycle detection has to
// be airtight. No mocks — pure data.

import 'package:ai_tutor_python/features/goals/tree_utils.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Goal g(String id, {String? parentId}) =>
      Goal(id: id, title: id, order: 0, parentId: parentId);

  group('buildParentMap', () {
    test('maps each id to its parentId, including null parents', () {
      final map = buildParentMap([
        g('root1'),
        g('root2'),
        g('child1', parentId: 'root1'),
        g('child2', parentId: 'root1'),
        g('grand1', parentId: 'child1'),
      ]);
      expect(map, {
        'root1': null,
        'root2': null,
        'child1': 'root1',
        'child2': 'root1',
        'grand1': 'child1',
      });
    });

    test('empty input → empty map', () {
      expect(buildParentMap(<Goal>[]), <String, String?>{});
    });
  });

  group('isAncestor', () {
    // Tree:
    //   root
    //   ├── a
    //   │   └── a1
    //   └── b
    final parentOf = <String, String?>{
      'root': null,
      'a': 'root',
      'a1': 'a',
      'b': 'root',
    };

    test('direct parent counts as ancestor', () {
      expect(isAncestor(parentOf, 'a', 'a1'), isTrue);
    });

    test('grandparent counts as ancestor', () {
      expect(isAncestor(parentOf, 'root', 'a1'), isTrue);
    });

    test('sibling is NOT an ancestor', () {
      expect(isAncestor(parentOf, 'a', 'b'), isFalse);
    });

    test('node is NOT its own ancestor', () {
      expect(isAncestor(parentOf, 'a', 'a'), isFalse);
    });

    test('null ancestorId never matches (the loop stops at null)', () {
      expect(isAncestor(parentOf, null, 'a1'), isFalse);
    });

    test('unknown nodeId → false (parentOf lookup is null)', () {
      expect(isAncestor(parentOf, 'root', 'ghost'), isFalse);
    });
  });

  group('wouldCreateCycle', () {
    // Same tree as above.
    final parentOf = <String, String?>{
      'root': null,
      'a': 'root',
      'a1': 'a',
      'b': 'root',
    };

    test('moving to root (newParentId == null) is always safe', () {
      expect(wouldCreateCycle(parentOf, 'a', null), isFalse);
      expect(wouldCreateCycle(parentOf, 'a1', null), isFalse);
      expect(wouldCreateCycle(parentOf, null, null), isFalse);
    });

    test('self-parent is a cycle', () {
      expect(wouldCreateCycle(parentOf, 'a', 'a'), isTrue);
    });

    test('moving a node under one of its descendants is a cycle', () {
      // 'a' is currently the parent of 'a1'. Re-parenting 'a' under 'a1'
      // would form a cycle.
      expect(wouldCreateCycle(parentOf, 'a', 'a1'), isTrue);
    });

    test('moving a node under its sibling is safe', () {
      expect(wouldCreateCycle(parentOf, 'a', 'b'), isFalse);
    });

    test('moving a node under an unrelated branch is safe', () {
      expect(wouldCreateCycle(parentOf, 'a1', 'b'), isFalse);
    });
  });
}
