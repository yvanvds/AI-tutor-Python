// Tests for GoalSelectionNotifier and GoalSelectionState.
// State is pure value objects + Riverpod mutations — no mocks required.

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Goal _g(String id) => Goal(id: id, title: 'Goal $id', order: 1000);

void main() {
  late ProviderContainer pc;

  setUp(() {
    pc = ProviderContainer();
  });

  tearDown(() {
    pc.dispose();
  });

  GoalSelectionNotifier notifier() => pc.read(goalSelectionProvider.notifier);

  GoalSelectionState state() => pc.read(goalSelectionProvider);

  group('initial state', () {
    test('all fields are null, cachedRoots is empty', () {
      final s = state();
      expect(s.selectedRoot, isNull);
      expect(s.selectedChild, isNull);
      expect(s.preferredRoot, isNull);
      expect(s.preferredChild, isNull);
      expect(s.editorSelectedRoot, isNull);
      expect(s.editorSelectedGoal, isNull);
      expect(s.cachedRoots, isEmpty);
    });
  });

  group('activeChildGoal / activeRootGoal', () {
    test('returns null when nothing is set', () {
      expect(state().activeChildGoal, isNull);
      expect(state().activeRootGoal, isNull);
    });

    test('activeChildGoal prefers preferredChild over selectedChild', () {
      notifier().setSelectedChild(_g('sel'));
      notifier().setPreferredChild(_g('pref'));
      expect(state().activeChildGoal?.id, 'pref');
    });

    test('activeChildGoal falls back to selectedChild when no preferred', () {
      notifier().setSelectedChild(_g('sel'));
      expect(state().activeChildGoal?.id, 'sel');
    });

    test('activeRootGoal prefers preferredRoot over selectedRoot', () {
      notifier().setSelectedRoot(_g('root-sel'));
      notifier().setPreferredRoot(_g('root-pref'));
      expect(state().activeRootGoal?.id, 'root-pref');
    });

    test('activeRootGoal falls back to selectedRoot when no preferred', () {
      notifier().setSelectedRoot(_g('root-sel'));
      expect(state().activeRootGoal?.id, 'root-sel');
    });
  });

  group('setSelectedRoot', () {
    test('sets the selectedRoot', () {
      notifier().setSelectedRoot(_g('r1'));
      expect(state().selectedRoot?.id, 'r1');
    });

    test('clears selectedRoot when null is passed', () {
      notifier().setSelectedRoot(_g('r1'));
      notifier().setSelectedRoot(null);
      expect(state().selectedRoot, isNull);
    });
  });

  group('setSelectedChild', () {
    test('sets the selectedChild', () {
      notifier().setSelectedChild(_g('c1'));
      expect(state().selectedChild?.id, 'c1');
    });

    test('clears selectedChild when null is passed', () {
      notifier().setSelectedChild(_g('c1'));
      notifier().setSelectedChild(null);
      expect(state().selectedChild, isNull);
    });
  });

  group('setPreferredRoot', () {
    test('sets preferredRoot', () {
      notifier().setPreferredRoot(_g('pr1'));
      expect(state().preferredRoot?.id, 'pr1');
    });

    test('clears preferredRoot when null is passed', () {
      notifier().setPreferredRoot(_g('pr1'));
      notifier().setPreferredRoot(null);
      expect(state().preferredRoot, isNull);
    });
  });

  group('setPreferredChild', () {
    test('sets preferredChild', () {
      notifier().setPreferredChild(_g('pc1'));
      expect(state().preferredChild?.id, 'pc1');
    });

    test('clears preferredChild when null is passed', () {
      notifier().setPreferredChild(_g('pc1'));
      notifier().setPreferredChild(null);
      expect(state().preferredChild, isNull);
    });
  });

  group('setEditorSelectedRoot', () {
    test('sets editorSelectedRoot', () {
      notifier().setEditorSelectedRoot(_g('er1'));
      expect(state().editorSelectedRoot?.id, 'er1');
    });

    test('clears editorSelectedRoot when null is passed', () {
      notifier().setEditorSelectedRoot(_g('er1'));
      notifier().setEditorSelectedRoot(null);
      expect(state().editorSelectedRoot, isNull);
    });
  });

  group('setEditorSelectedGoal', () {
    test('sets editorSelectedGoal', () {
      notifier().setEditorSelectedGoal(_g('eg1'));
      expect(state().editorSelectedGoal?.id, 'eg1');
    });

    test('clears editorSelectedGoal when null is passed', () {
      notifier().setEditorSelectedGoal(_g('eg1'));
      notifier().setEditorSelectedGoal(null);
      expect(state().editorSelectedGoal, isNull);
    });
  });

  group('setCachedRoots', () {
    test('replaces cachedRoots with the supplied list', () {
      notifier().setCachedRoots([_g('r1'), _g('r2')]);
      expect(state().cachedRoots.map((g) => g.id).toList(), ['r1', 'r2']);
    });

    test('clearing via empty list works', () {
      notifier().setCachedRoots([_g('r1')]);
      notifier().setCachedRoots([]);
      expect(state().cachedRoots, isEmpty);
    });
  });

  group('GoalSelectionState.copyWith — independent field updates', () {
    test('updating one field leaves others unchanged', () {
      notifier().setSelectedRoot(_g('r1'));
      notifier().setSelectedChild(_g('c1'));
      // Updating only selectedRoot should not touch selectedChild.
      notifier().setSelectedRoot(_g('r2'));
      expect(state().selectedRoot?.id, 'r2');
      expect(state().selectedChild?.id, 'c1');
    });
  });

  group('chooseSubgoal — a subgoal picked back up in the Leerpad (#280)', () {
    test("prefers the subgoal and its root, as the student's own choice; "
        'the selection — the goal in progress — stays', () {
      notifier().setSelectedRoot(_g('now'));
      notifier().setSelectedChild(_g('now-sub'));
      expect(state().isSelfChosen, isFalse);

      notifier().chooseSubgoal(root: _g('old'), child: _g('old-sub'));

      expect(state().isSelfChosen, isTrue);
      expect(state().activeRootGoal?.id, 'old');
      expect(state().activeChildGoal?.id, 'old-sub');
      expect(state().selectedRoot?.id, 'now');
      expect(state().selectedChild?.id, 'now-sub');
    });

    test('"Verder" — a root preferred without a child — ends it', () {
      notifier().chooseSubgoal(root: _g('old'), child: _g('old-sub'));
      notifier().setPreferredRoot(_g('now'));
      // The root alone leaves the choice: the child goes with it.
      expect(state().isSelfChosen, isTrue);
      notifier().setPreferredChild(null);
      expect(state().isSelfChosen, isFalse);
      expect(state().activeRootGoal?.id, 'now');
    });

    test("a preferred child set otherwise is no choice of the student's, "
        'and clearing the preferences ends one', () {
      notifier().chooseSubgoal(root: _g('old'), child: _g('old-sub'));
      notifier().setPreferredChild(_g('other'));
      expect(state().isSelfChosen, isFalse);

      notifier().chooseSubgoal(root: _g('old'), child: _g('old-sub'));
      final cleared = state().copyWith(
        clearPreferredRoot: true,
        clearPreferredChild: true,
      );
      expect(cleared.isSelfChosen, isFalse);
      // And it does not come back with the next child.
      expect(
        cleared.copyWith(preferredChild: _g('next')).isSelfChosen,
        isFalse,
      );
    });

    test('other updates keep it', () {
      notifier().chooseSubgoal(root: _g('old'), child: _g('old-sub'));
      notifier().setSelectedRoot(_g('r2'));
      notifier().setCachedRoots([_g('r1')]);
      expect(state().isSelfChosen, isTrue);
    });
  });
}
