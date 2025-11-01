import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'report_repository.dart';
import 'status_report.dart';

/// Singleton repository.
final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository();
});

/// Load all status reports once (e.g., for initial decision logic in your Tutor).
final statusReportListProviderFuture =
    FutureProvider.autoDispose<List<StatusReport>>((ref) async {
      final repo = ref.read(reportRepositoryProvider);
      return repo.getAll();
    });

/// Realtime stream of all status reports (use in UI if you want live updates).
final statusReportListProviderStream = StreamProvider<List<StatusReport>>((
  ref,
) {
  final repo = ref.read(reportRepositoryProvider);
  return repo.watchAll();
});

/// Get a single goal’s status report once.
final statusReportByGoalProviderFuture = FutureProvider.autoDispose
    .family<StatusReport?, String>((ref, goalID) {
      final repo = ref.read(reportRepositoryProvider);
      return repo.getByGoalId(goalID);
    });

/// Upsert (create or update) a StatusReport doc.
final upsertStatusReportProviderFuture =
    FutureProvider.family<void, StatusReport>((ref, statusReport) async {
      final repo = ref.read(reportRepositoryProvider);
      await repo.upsert(statusReport);
    });
