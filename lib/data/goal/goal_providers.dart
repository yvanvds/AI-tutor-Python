// Repository provider
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository();
});

/// Stream of root goals (StreamProvider is fine to keep)
final rootGoalsProviderStream = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  return repo.streamRoots();
});

// load goals once (e.g., for initial decision logic in your Tutor)
final rootGoalsProviderFuture = FutureProvider<List<Goal>>((ref) async {
  final repo = ref.watch(goalsRepositoryProvider);
  final roots = await repo.streamRoots().first;
  return roots;
});

// Selected root goal id state
class SelectedRootGoal extends Notifier<String?> {
  @override
  String? build() => null; // no selection initially
  void select(String? id) => state = id;
  void clear() => state = null;
}

// Selected root goal id (for viewing its children)
final selectedRootGoalProvider = NotifierProvider<SelectedRootGoal, String?>(
  SelectedRootGoal.new,
);

/// Stream of children for the selected root
final childGoalsProviderStream = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  final rootId = ref.watch(selectedRootGoalProvider);
  if (rootId == null) return const Stream<List<Goal>>.empty();
  return repo.streamChildren(rootId);
});

final childGoalsByParentProviderStream =
    StreamProvider.family<List<Goal>, String>((ref, parentId) {
      final repo = ref.watch(goalsRepositoryProvider);
      return repo.streamChildren(parentId);
    });

// load children once (e.g., for initial decision logic in your Tutor)
final childGoalsByParentProviderFuture =
    FutureProvider.family<List<Goal>, String>((ref, parentId) async {
      final repo = ref.watch(goalsRepositoryProvider);
      final children = await repo.streamChildren(parentId).first;
      return children;
    });

class SelectedChildGoal extends Notifier<String?> {
  @override
  String? build() => null; // no selection initially
  void select(String? id) => state = id;
  void clear() => state = null;
}

final selectedChildGoalProvider = NotifierProvider<SelectedChildGoal, String?>(
  SelectedChildGoal.new,
);
