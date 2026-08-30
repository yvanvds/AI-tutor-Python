// Issue #4 — content docs left behind by a Replace import (old subgoal ids
// deleted, content keyed by those ids kept) must be detectable so the
// Lesinhoud editor can surface and reassign them.

import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/orphaned_content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter_test/flutter_test.dart';

Content _c(String id) => Content(id: id, title: 'T $id', body: '<p>$id</p>');

void main() {
  group('orphanedContent', () {
    test('returns content no goal references via contentId', () {
      final goals = [
        Goal(id: 'r1', title: 'Root', order: 1000),
        Goal(id: 's-new', title: 'New', parentId: 'r1', order: 1000),
        Goal(
          id: 's-linked',
          title: 'Linked',
          parentId: 'r1',
          order: 2000,
          contentId: 's-linked',
        ),
      ];
      final contents = [_c('s-linked'), _c('s-old'), _c('s-older')];

      final out = orphanedContent(goals, contents);
      expect(out.map((c) => c.id).toList(), ['s-old', 's-older']);
    });

    test('a goal with the same id but no contentId does not claim the doc', () {
      // Teacher unlinked it via "Loskoppelen": the doc is unreferenced and
      // should show up so it can be relinked.
      final goals = [Goal(id: 's1', title: 'S', parentId: 'r', order: 1000)];
      expect(orphanedContent(goals, [_c('s1')]).map((c) => c.id), ['s1']);
    });

    test('empty contentId strings are ignored as references', () {
      final goals = [
        Goal(id: 's1', title: 'S', parentId: 'r', order: 1000, contentId: ''),
      ];
      expect(orphanedContent(goals, [_c('x')]).map((c) => c.id), ['x']);
    });

    test('no orphans when every doc is referenced', () {
      final goals = [
        Goal(id: 's1', title: 'S', parentId: 'r', order: 1, contentId: 's1'),
      ];
      expect(orphanedContent(goals, [_c('s1')]), isEmpty);
      expect(orphanedContent(goals, const []), isEmpty);
    });
  });
}
