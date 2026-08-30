import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/status_report/status_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collapsible per-subgoal AI status reports for one student.
class StatusReportsSection extends ConsumerWidget {
  const StatusReportsSection({
    super.key,
    required this.uid,
    required this.goals,
  });

  final String uid;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return StreamBuilder<List<StatusReport>>(
      stream: ref.read(reportServiceProvider).watchStatusReportsForUser(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return _section(
            theme,
            l,
            child: Text(
              l.drawer_statusReports_loadError,
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        if (!snap.hasData) {
          return _section(
            theme,
            l,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        }
        final reports = [...snap.data!]
          ..sort((a, b) {
            final ad = a.updatedAt;
            final bd = b.updatedAt;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });
        if (reports.isEmpty) {
          return _section(
            theme,
            l,
            child: Text(
              l.drawer_statusReports_empty,
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        final goalById = {for (final g in goals) g.id: g};
        return _section(
          theme,
          l,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in reports)
                _ReportTile(report: r, goal: goalById[r.goalID]),
            ],
          ),
        );
      },
    );
  }

  Widget _section(
    ThemeData theme,
    AppLocalizations l, {
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.drawer_statusReports_title,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.goal});

  final StatusReport report;
  final Goal? goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = goal?.title ?? report.goalID;
    final updated = report.updatedAt;
    final subtitle = updated == null ? null : formatTs(updated, context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null ? null : Text(subtitle),
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            report.statusReport,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
