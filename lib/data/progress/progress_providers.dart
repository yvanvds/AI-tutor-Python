import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'progress_repository.dart';
import 'progress.dart';

/// Singleton repository.
final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository();
});

/// Load all progress once (e.g., for initial decision logic in your Tutor).
final progressListProviderFuture = FutureProvider.autoDispose<List<Progress>>((
  ref,
) async {
  final repo = ref.read(progressRepositoryProvider);
  return repo.getAll();
});

/// Realtime stream of all progress (use in UI if you want live updates).
final progressListProviderStream = StreamProvider<List<Progress>>((ref) {
  final repo = ref.read(progressRepositoryProvider);
  return repo.watchAll();
});

/// Get a single goal’s progress once.
final progressByGoalProviderFuture = FutureProvider.autoDispose
    .family<Progress?, String>((ref, goalID) {
      final repo = ref.read(progressRepositoryProvider);
      return repo.getByGoalId(goalID);
    });

// Live progress for a single goal (stream)
final progressByGoalProvider = StreamProvider.family<Progress?, String>((
  ref,
  goalID,
) {
  final repo = ref.read(progressRepositoryProvider);
  return repo.streamByGoalId(goalID); // implement in your repo if missing
});

/// Upsert (create or update) a Progress doc.
final upsertProgressProviderFuture = FutureProvider.family<void, Progress>((
  ref,
  progress,
) async {
  final repo = ref.read(progressRepositoryProvider);
  await repo.upsert(progress);
});
