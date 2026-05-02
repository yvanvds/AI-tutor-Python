import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter/material.dart';

/// One-line status banner for the detail drawer header. Computes the same
/// active/idle/struggling bucket as the inline accounts column, plus a
/// concept-attribution breakdown when the student is struggling.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (status == StudentStatus.struggling && reference != null)
            _ConceptHaperLine(progress: reference),
        ],
      ),
    );
  }

  String _summary(StudentStatus status, Goal? activeGoal) {
    final on = activeGoal == null ? '' : ' op "${activeGoal.title}"';
    switch (status) {
      case StudentStatus.struggling:
        return 'Heeft het moeilijk$on.';
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
      StudentStatus.struggling => Colors.red.shade400,
      StudentStatus.active => Colors.green.shade400,
      StudentStatus.idle => Colors.grey.shade400,
    };
    return Tooltip(
      message: switch (status) {
        StudentStatus.struggling =>
          'Recente antwoorden tonen veel fouten op dit subdoel.',
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

class _ConceptHaperLine extends StatelessWidget {
  const _ConceptHaperLine({required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final ranked = rankConceptAttributions(progress.recentConceptAttributions);
    if (ranked.isEmpty) return const SizedBox.shrink();
    final top = ranked.take(2).toList();
    final rendered = top.map((e) => '${e.key} (${e.value}×)').join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 20),
      child: Text(
        'Lijkt te haperen op: $rendered',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
