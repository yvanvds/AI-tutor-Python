// Repository provider
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository();
});

/// Stream of root goals (StreamProvider is fine to keep)
final rootGoalsProvider = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  return repo.streamRoots();
});

// Selected root goal id state
class SelectedRootId extends Notifier<String?> {
  @override
  String? build() => null; // no selection initially
  void select(String? id) => state = id;
  void clear() => state = null;
}

// Selected root goal id (for viewing its children)
final selectedRootIdProvider = NotifierProvider<SelectedRootId, String?>(
  SelectedRootId.new,
);

/// Stream of children for the selected root
final childGoalsProvider = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  final rootId = ref.watch(selectedRootIdProvider);
  if (rootId == null) return const Stream<List<Goal>>.empty();
  return repo.streamChildren(rootId);
});
