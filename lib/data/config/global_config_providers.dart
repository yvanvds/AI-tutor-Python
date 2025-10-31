import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'global_config.dart';
import 'global_config_repository.dart';

/// Repository provider (read-only)
final globalConfigRepositoryProvider = Provider<GlobalConfigRepository>((ref) {
  return GlobalConfigRepository();
});

/// Fetch once: `final cfg = ref.watch(globalConfigFutureProvider).value;`
final globalConfigFutureProvider = FutureProvider<GlobalConfig?>((ref) async {
  final repo = ref.watch(globalConfigRepositoryProvider);
  return repo.getConfig();
});

/// Live updates: `ref.watch(globalConfigStreamProvider).value`
final globalConfigStreamProvider = StreamProvider<GlobalConfig?>((ref) {
  final repo = ref.watch(globalConfigRepositoryProvider);
  return repo.watchConfig();
});

/// Convenient selectors (optional)
final modelProvider = Provider<String?>((ref) {
  final cfg = ref
      .watch(globalConfigFutureProvider)
      .maybeWhen(data: (c) => c, orElse: () => null);
  return cfg?.model;
});

final apiKeyProvider = Provider<String?>((ref) {
  final cfg = ref
      .watch(globalConfigFutureProvider)
      .maybeWhen(data: (c) => c, orElse: () => null);
  return cfg?.apiKey;
});
