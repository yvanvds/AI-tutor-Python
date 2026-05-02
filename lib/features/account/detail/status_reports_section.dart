import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/status_report/status_report.dart';
import 'package:flutter/material.dart';

/// Collapsible per-subgoal AI status reports for one student. Section header
/// is always visible; each subgoal that has a report renders as an
/// `ExpansionTile`. Most-recently-updated reports come first.
class StatusReportsSection extends StatelessWidget {
  const StatusReportsSection({
    super.key,
    required this.uid,
    required this.goals,
  });

  final String uid;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<StatusReport>>(
      stream: DataService.report.watchStatusReportsForUser(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return _section(
            theme,
            child: Text(
              'Kon de statusrapporten niet laden.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        if (!snap.hasData) {
          return _section(
            theme,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          );
        }
        final reports = [...snap.data!]..sort((a, b) {
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
            child: Text(
              'Nog geen statusrapporten.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        final goalById = {for (final g in goals) g.id: g};
        return _section(
          theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in reports)
                _ReportTile(
                  report: r,
                  goal: goalById[r.goalID],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(ThemeData theme, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Statusrapporten', style: theme.textTheme.titleMedium),
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
    final subtitle = updated == null ? null : _formatTs(updated);
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

  String _formatTs(DateTime ts) {
    final dt = ts.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
