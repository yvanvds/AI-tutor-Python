// Pure row model + sorting for the Students page table (#87). Kept out of
// the widget so the comparators are unit-testable and so the per-account
// derived values (progress, goal titles, status) are computed once per
// account per build and shared between sorting and rendering.

import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';

/// Everything one table row needs beyond the raw [Account], computed once
/// per account (not once per visible cell) so the full — unpaginated — list
/// can be sorted on the same values the rows render.
class StudentRowData {
  final Account account;

  /// The "Last active" timestamp shown under the email (account-level
  /// activity: `updatedAt` falling back to `createdAt`).
  final DateTime? lastActive;

  /// Titles for the "Current goal" cell (#88); null in the em-dash cases.
  final ({String rootTitle, String? subgoalTitle})? goalTitles;

  /// Progress of the active root goal (#89), 0.0–1.0.
  final double overallProgress;

  /// Active/idle dot for the Status column.
  final StudentStatus status;

  const StudentRowData({
    required this.account,
    required this.lastActive,
    required this.goalTitles,
    required this.overallProgress,
    required this.status,
  });

  /// Hoisted per-account computation: delegates to the same pure helpers
  /// the cells used to call individually ([activeGoalTitles],
  /// [activeRootProgress], [computeStudentStatus]).
  factory StudentRowData.compute(
    Account account, {
    required List<Progress> progress,
    required Map<String, Goal> goalById,
    required Map<String, String?> parentByChild,
    DateTime? now,
  }) {
    return StudentRowData(
      account: account,
      lastActive: account.updatedAt ?? account.createdAt,
      goalTitles: activeGoalTitles(
        progress: progress,
        goalById: goalById,
        parentByChild: parentByChild,
      ),
      overallProgress: activeRootProgress(
        progress: progress,
        goalById: goalById,
        parentByChild: parentByChild,
      ),
      status: computeStudentStatus(progress: progress, now: now),
    );
  }
}

/// Sortable columns of the students table. The page maps its
/// `DataColumn` indices onto these keys.
enum StudentsSortKey {
  /// Email, case-insensitive.
  email,

  /// Name: last name first, then first name, case-insensitive.
  name,

  /// Class tag, case-insensitive; students without a class sort together.
  className,

  /// The active root goal's title, case-insensitive; students without a
  /// current goal (the em-dash rows) sort as an empty title.
  currentGoal,

  /// Overall progress value of the active root (#89).
  progress,

  /// Status severity — active before idle — with the account's last-active
  /// timestamp (most recent first) breaking ties inside each bucket, so a
  /// status sort also orders students by how recently they were active.
  status,
}

int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1; // never active sorts as oldest
  if (b == null) return 1;
  return a.compareTo(b);
}

/// Comparator for one sort key, ascending. Ties are NOT broken here —
/// [sortStudentRows] appends a uid tiebreak for determinism.
int compareStudentRows(
  StudentRowData a,
  StudentRowData b,
  StudentsSortKey key,
) {
  switch (key) {
    case StudentsSortKey.email:
      return a.account.email.toLowerCase().compareTo(
        b.account.email.toLowerCase(),
      );
    case StudentsSortKey.name:
      final byLast = a.account.lastName.toLowerCase().compareTo(
        b.account.lastName.toLowerCase(),
      );
      if (byLast != 0) return byLast;
      return a.account.firstName.toLowerCase().compareTo(
        b.account.firstName.toLowerCase(),
      );
    case StudentsSortKey.className:
      return a.account.className.toLowerCase().compareTo(
        b.account.className.toLowerCase(),
      );
    case StudentsSortKey.currentGoal:
      final at = a.goalTitles?.rootTitle.toLowerCase() ?? '';
      final bt = b.goalTitles?.rootTitle.toLowerCase() ?? '';
      return at.compareTo(bt);
    case StudentsSortKey.progress:
      return a.overallProgress.compareTo(b.overallProgress);
    case StudentsSortKey.status:
      // StudentStatus declares active before idle, so the enum index is the
      // severity rank.
      final byStatus = a.status.index.compareTo(b.status.index);
      if (byStatus != 0) return byStatus;
      // Most recently active first within the same status bucket.
      return -_compareNullableDates(a.lastActive, b.lastActive);
  }
}

/// Sorts [rows] in place by [key]. Dart's `List.sort` is not stable, so a
/// uid tiebreak keeps equal-keyed rows in a deterministic order across
/// rebuilds (a re-render must not shuffle visually identical rows).
void sortStudentRows(
  List<StudentRowData> rows, {
  required StudentsSortKey key,
  required bool ascending,
}) {
  rows.sort((a, b) {
    var c = compareStudentRows(a, b, key);
    if (c == 0) c = a.account.uid.compareTo(b.account.uid);
    return ascending ? c : -c;
  });
}
