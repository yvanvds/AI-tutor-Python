// Repository provider
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  return GoalsRepository();
});

// Selected root goal id state
class SelectedRootGoal extends Notifier<String?> {
  @override
  String? build() => null; // no selection initially
  void select(String? id) => state = id;
  void clear() => state = null;
}

/// Which goal is being edited in the drawer? (null = closed)
class EditingGoalId extends Notifier<String?> {
  @override
  String? build() => null;
  void open(String id) => state = id;
  void close() => state = null;
}

class SelectedChildGoal extends Notifier<String?> {
  @override
  String? build() => null; // no selection initially
  void select(String? id) => state = id;
  void clear() => state = null;
}

final selectedChildGoalProviderNotifier =
    NotifierProvider<SelectedChildGoal, String?>(SelectedChildGoal.new);

// Selected root goal id (for viewing its children)
final selectedRootGoalProviderNotifier =
    NotifierProvider<SelectedRootGoal, String?>(SelectedRootGoal.new);

// Editing goal id state
final editingGoalIdProviderNotifier = NotifierProvider<EditingGoalId, String?>(
  EditingGoalId.new,
);

/// Stream of root goals (StreamProvider is fine to keep)
final rootGoalsProviderStream = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  return repo.streamRoots();
});

// load goals once (e.g., for initial decision logic in your Tutor)
final rootGoalsProviderFuture = FutureProvider.autoDispose<List<Goal>>((
  ref,
) async {
  final repo = ref.watch(goalsRepositoryProvider);
  final roots = await repo.streamRoots().first;
  return roots;
});

/// Stream of children for the selected root
final childGoalsProviderStream = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalsRepositoryProvider);
  final rootId = ref.watch(selectedRootGoalProviderNotifier);
  if (rootId == null) return const Stream<List<Goal>>.empty();
  return repo.streamChildren(rootId);
});

final childGoalsByParentProviderStream =
    StreamProvider.family<List<Goal>, String>((ref, parentId) {
      final repo = ref.watch(goalsRepositoryProvider);
      return repo.streamChildren(parentId);
    });

// load children once (e.g., for initial decision logic in your Tutor)
final childGoalsByParentProviderFuture = FutureProvider.autoDispose
    .family<List<Goal>, String>((ref, parentId) async {
      final repo = ref.watch(goalsRepositoryProvider);
      final children = await repo.streamChildren(parentId).first;
      return children;
    });

/// Stream the single goal being edited
final editingGoalProviderStream = StreamProvider<Goal?>((ref) {
  final id = ref.watch(editingGoalIdProviderNotifier);
  if (id == null) return const Stream.empty();
  final repo = ref.watch(goalsRepositoryProvider);
  return repo.streamGoal(id); // ← direct single-doc stream
});

// If you don’t already have a by-id stream, add this:
final goalByIdProvider = StreamProvider.family<Goal?, String>((ref, id) {
  final repo = ref.read(goalsRepositoryProvider);
  return repo.streamGoal(id); // implement in your repo if missing
});
