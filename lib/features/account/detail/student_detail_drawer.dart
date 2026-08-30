import 'package:ai_tutor_python/features/account/detail/progress_history_charts.dart';
import 'package:ai_tutor_python/features/account/detail/signal_events_section.dart';
import 'package:ai_tutor_python/features/account/detail/status_reports_section.dart';
import 'package:ai_tutor_python/features/account/detail/student_status_summary.dart';
import 'package:ai_tutor_python/features/progress/student_progress_list.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Right-hand peek panel for one student.
class StudentDetailDrawer extends ConsumerWidget {
  const StudentDetailDrawer({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                stream: ref.read(goalsServiceProvider).streamAllGoals(),
                builder: (context, goalsSnap) {
                  final goals = goalsSnap.data ?? const <Goal>[];
                  return StreamBuilder<List<Progress>>(
                    stream: ref
                        .read(progressServiceProvider)
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
                          SignalEventsSection(uid: account.uid),
                          const Divider(height: 1),
                          _SectionTitle(
                            theme: theme,
                            label: AppLocalizations.of(
                              context,
                            ).drawer_section_goals,
                          ),
                          SizedBox(
                            height: 320,
                            child: StudentProgressList(uid: account.uid),
                          ),
                          const Divider(height: 1),
                          StatusReportsSection(uid: account.uid, goals: goals),
                          const Divider(height: 1),
                          ProgressHistoryCharts(uid: account.uid, goals: goals),
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
                  Text(account.email, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).drawer_close_tooltip,
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
