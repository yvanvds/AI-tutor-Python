import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter/material.dart';

/// One-line status banner for the detail drawer header. Computes the same
/// active/idle bucket as the inline accounts column.
class StudentStatusSummary extends StatelessWidget {
  const StudentStatusSummary({
    super.key,
    required this.progress,
    required this.goals,
  });

  final List<Progress> progress;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = computeStudentStatus(progress: progress);
    final reference = mostRecentlyActive(progress);

    final goalById = {for (final g in goals) g.id: g};
    final activeGoal =
        reference == null ? null : goalById[reference.goalID];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _summary(status, activeGoal),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _summary(StudentStatus status, Goal? activeGoal) {
    final on = activeGoal == null ? '' : ' op "${activeGoal.title}"';
    switch (status) {
      case StudentStatus.active:
        return 'Recent actief$on.';
      case StudentStatus.idle:
        return 'Geen recente activiteit.';
    }
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final StudentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StudentStatus.active => Colors.green.shade400,
      StudentStatus.idle => Colors.grey.shade400,
    };
    return Tooltip(
      message: switch (status) {
        StudentStatus.active => 'Recent vooruitgang geboekt.',
        StudentStatus.idle => 'Geen vooruitgang in de laatste 7 dagen.',
      },
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
