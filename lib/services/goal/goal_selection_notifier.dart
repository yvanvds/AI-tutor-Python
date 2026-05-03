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
  });

  /// Active root / child goal for the student flow.
  final Goal? selectedRoot;
  final Goal? selectedChild;

  /// Preferred root / child goal overrides set by teacher or fast-forward.
  final Goal? preferredRoot;
  final Goal? preferredChild;

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
  }) {
    return GoalSelectionState(
      selectedRoot: clearSelectedRoot ? null : (selectedRoot ?? this.selectedRoot),
      selectedChild: clearSelectedChild ? null : (selectedChild ?? this.selectedChild),
      preferredRoot: clearPreferredRoot ? null : (preferredRoot ?? this.preferredRoot),
      preferredChild: clearPreferredChild ? null : (preferredChild ?? this.preferredChild),
      editorSelectedRoot: clearEditorSelectedRoot ? null : (editorSelectedRoot ?? this.editorSelectedRoot),
      editorSelectedGoal: clearEditorSelectedGoal ? null : (editorSelectedGoal ?? this.editorSelectedGoal),
      cachedRoots: cachedRoots ?? this.cachedRoots,
    );
  }
}

class GoalSelectionNotifier extends Notifier<GoalSelectionState> {
  @override
  GoalSelectionState build() => const GoalSelectionState();

  void setSelectedRoot(Goal? goal) =>
      state = state.copyWith(
        selectedRoot: goal,
        clearSelectedRoot: goal == null,
      );

  void setSelectedChild(Goal? goal) =>
      state = state.copyWith(
        selectedChild: goal,
        clearSelectedChild: goal == null,
      );

  void setPreferredRoot(Goal? goal) =>
      state = state.copyWith(
        preferredRoot: goal,
        clearPreferredRoot: goal == null,
      );

  void setPreferredChild(Goal? goal) =>
      state = state.copyWith(
        preferredChild: goal,
        clearPreferredChild: goal == null,
      );

  void setEditorSelectedRoot(Goal? goal) =>
      state = state.copyWith(
        editorSelectedRoot: goal,
        clearEditorSelectedRoot: goal == null,
      );

  void setEditorSelectedGoal(Goal? goal) =>
      state = state.copyWith(
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
