import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'progress_repository.dart';
import 'progress.dart';

/// Singleton repository.
final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository();
});

/// Load all progress once (e.g., for initial decision logic in your Tutor).
final progressListFutureProvider = FutureProvider<List<Progress>>((ref) async {
  final repo = ref.read(progressRepositoryProvider);
  return repo.getAll();
});

/// Realtime stream of all progress (use in UI if you want live updates).
final progressListStreamProvider = StreamProvider<List<Progress>>((ref) {
  final repo = ref.read(progressRepositoryProvider);
  return repo.watchAll();
});

/// Get a single goal’s progress once.
final progressByGoalFutureProvider = FutureProvider.family<Progress?, String>((
  ref,
  goalID,
) {
  final repo = ref.read(progressRepositoryProvider);
  return repo.getByGoalId(goalID);
});

/// Upsert (create or update) a Progress doc.
final upsertProgressProvider = FutureProvider.family<void, Progress>((
  ref,
  progress,
) async {
  final repo = ref.read(progressRepositoryProvider);
  await repo.upsert(progress);
});
