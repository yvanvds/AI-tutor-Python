import 'package:ai_tutor_python/features/account/detail/progress_history_charts.dart';
import 'package:ai_tutor_python/features/account/detail/status_reports_section.dart';
import 'package:ai_tutor_python/features/account/detail/student_status_summary.dart';
import 'package:ai_tutor_python/features/progress/student_progress_list.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';

/// Right-hand peek panel for one student. Shown via the accounts page on
/// row tap. Loads:
///
/// - The student's progress docs (per-subgoal table + status summary).
/// - The student's status reports (collapsible per-subgoal section).
/// - The student's progress history (per-root-goal line chart).
///
/// Each section streams independently so the drawer can progressively
/// reveal content rather than block on the slowest read.
class StudentDetailDrawer extends StatelessWidget {
  const StudentDetailDrawer({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.of(context).size.width;
    final width = (mediaWidth * 0.45).clamp(380.0, 720.0);

    return Drawer(
      width: width,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(account: account, onClose: () => Navigator.pop(context)),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<Goal>>(
                stream: DataService.goals.streamAllGoals(),
                builder: (context, goalsSnap) {
                  final goals = goalsSnap.data ?? const <Goal>[];
                  return StreamBuilder<List<Progress>>(
                    stream: DataService.progress
                        .watchProgressForUser(account.uid),
                    builder: (context, progSnap) {
                      final progress = progSnap.data ?? const <Progress>[];
                      return ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (!progSnap.hasData)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(minHeight: 2),
                            )
                          else
                            StudentStatusSummary(
                              progress: progress,
                              goals: goals,
                            ),
                          const Divider(height: 1),
                          _SectionTitle(theme: theme, label: 'Doelen'),
                          SizedBox(
                            height: 320,
                            child: StudentProgressList(uid: account.uid),
                          ),
                          const Divider(height: 1),
                          StatusReportsSection(
                            uid: account.uid,
                            goals: goals,
                          ),
                          const Divider(height: 1),
                          ProgressHistoryCharts(
                            uid: account.uid,
                            goals: goals,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.account, required this.onClose});

  final Account account;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.fullName.trim().isEmpty
                      ? account.email
                      : account.fullName,
                  style: theme.textTheme.titleMedium,
                ),
                if (account.fullName.trim().isNotEmpty)
                  Text(
                    account.email,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sluiten',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label, style: theme.textTheme.titleMedium),
    );
  }
}
