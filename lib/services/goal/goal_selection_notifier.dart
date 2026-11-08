import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable snapshot of all "selected goal" state that was previously spread
/// across six ValueNotifiers on GoalsService. The GoalSelectionNotifier owns
/// mutations; everything else reads via ref.watch(goalSelectionProvider).
@immutable
class GoalSelectionState {
  const GoalSelectionState({
    this.selectedRoot,
    this.selectedChild,
    this.preferredRoot,
    this.preferredChild,
    this.editorSelectedRoot,
    this.editorSelectedGoal,
    this.cachedRoots = const [],
    this._selfChosen = false,
  });

  /// Active root / child goal for the student flow.
  final Goal? selectedRoot;
  final Goal? selectedChild;

  /// Preferred root / child goal overrides set by teacher or fast-forward,
  /// "Verder" on a root in the Leerpad, or a subgoal the student picked
  /// back up there ([isSelfChosen], #280).
  final Goal? preferredRoot;
  final Goal? preferredChild;

  /// Read through [isSelfChosen]: it holds only with a preferred child.
  final bool _selfChosen;

  /// Goal selected in the teacher's goal editor.
  final Goal? editorSelectedRoot;
  final Goal? editorSelectedGoal;

  /// Latest snapshot from the polling root-goals stream; synchronous
  /// fast-path used by the AI request loop to avoid a Cosmos round-trip.
  final List<Goal> cachedRoots;

  /// The child goal the conductor should work against: explicit preferred
  /// override first, then the regular selection.
  Goal? get activeChildGoal => preferredChild ?? selectedChild;

  /// The root goal the conductor should work against.
  Goal? get activeRootGoal => preferredRoot ?? selectedRoot;

  /// The student picked [preferredChild] back up from its chip in the
  /// Leerpad, to finish or to review it (#280, CONDUCTOR_POLICY §1.6): the
  /// conductor works on it — and on its root, [preferredRoot] — until the
  /// student goes back with "Verder". [selectedRoot] and [selectedChild]
  /// stay the goal in progress, the one "Verder" returns to.
  bool get isSelfChosen => _selfChosen && preferredChild != null;

  GoalSelectionState copyWith({
    Goal? selectedRoot,
    Goal? selectedChild,
    Goal? preferredRoot,
    Goal? preferredChild,
    Goal? editorSelectedRoot,
    Goal? editorSelectedGoal,
    List<Goal>? cachedRoots,
    bool clearSelectedRoot = false,
    bool clearSelectedChild = false,
    bool clearPreferredRoot = false,
    bool clearPreferredChild = false,
    bool clearEditorSelectedRoot = false,
    bool clearEditorSelectedGoal = false,
    bool? selfChosen,
  }) {
    return GoalSelectionState(
      selectedRoot: clearSelectedRoot
          ? null
          : (selectedRoot ?? this.selectedRoot),
      selectedChild: clearSelectedChild
          ? null
          : (selectedChild ?? this.selectedChild),
      preferredRoot: clearPreferredRoot
          ? null
          : (preferredRoot ?? this.preferredRoot),
      preferredChild: clearPreferredChild
          ? null
          : (preferredChild ?? this.preferredChild),
      editorSelectedRoot: clearEditorSelectedRoot
          ? null
          : (editorSelectedRoot ?? this.editorSelectedRoot),
      editorSelectedGoal: clearEditorSelectedGoal
          ? null
          : (editorSelectedGoal ?? this.editorSelectedGoal),
      cachedRoots: cachedRoots ?? this.cachedRoots,
      // A preference that goes, goes with its reason (#280).
      selfChosen: clearPreferredChild ? false : (selfChosen ?? _selfChosen),
    );
  }
}

class GoalSelectionNotifier extends Notifier<GoalSelectionState> {
  @override
  GoalSelectionState build() => const GoalSelectionState();

  /// Public read-only view of the current state, for callers that hold the
  /// notifier directly (e.g. after a WidgetRef has been disposed).
  GoalSelectionState get current => state;

  void setSelectedRoot(Goal? goal) => state = state.copyWith(
    selectedRoot: goal,
    clearSelectedRoot: goal == null,
  );

  void setSelectedChild(Goal? goal) => state = state.copyWith(
    selectedChild: goal,
    clearSelectedChild: goal == null,
  );

  void setPreferredRoot(Goal? goal) => state = state.copyWith(
    preferredRoot: goal,
    clearPreferredRoot: goal == null,
  );

  /// A preferred child set here is not one the student chose
  /// ([GoalSelectionState.isSelfChosen]); [chooseSubgoal] sets that one.
  void setPreferredChild(Goal? goal) => state = state.copyWith(
    preferredChild: goal,
    clearPreferredChild: goal == null,
    selfChosen: false,
  );

  /// The student picks [child] of [root] back up from the Leerpad (#280):
  /// both become the preference, marked as the student's own choice. The
  /// selection — the goal in progress — stays as it is.
  void chooseSubgoal({required Goal root, required Goal child}) => state = state
      .copyWith(preferredRoot: root, preferredChild: child, selfChosen: true);

  void setEditorSelectedRoot(Goal? goal) => state = state.copyWith(
    editorSelectedRoot: goal,
    clearEditorSelectedRoot: goal == null,
  );

  void setEditorSelectedGoal(Goal? goal) => state = state.copyWith(
    editorSelectedGoal: goal,
    clearEditorSelectedGoal: goal == null,
  );

  void setCachedRoots(List<Goal> roots) =>
      state = state.copyWith(cachedRoots: List.unmodifiable(roots));
}

final goalSelectionProvider =
    NotifierProvider<GoalSelectionNotifier, GoalSelectionState>(
      GoalSelectionNotifier.new,
    );
