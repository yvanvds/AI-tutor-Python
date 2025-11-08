import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';
import 'package:ai_tutor_python/widgets/multi_value_listenable_builder.dart';

class GoalCrumbInAppBar extends StatelessWidget {
  const GoalCrumbInAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiValueListenableBuilder(
      listenables: [
        DataService.goals.selectedRootGoal,
        DataService.goals.selectedChildGoal,
        DataService.goals.preferredRootGoal,
        DataService.goals.preferredChildGoal,
        DataService.progress.currentProgress,
      ],
      builder: (context, values) {
        final root = values[2]?.title ?? values[0]?.title ?? "";
        final child = values[3]?.title ?? values[1]?.title ?? "";
        final progress = values[4] ?? 0.0;

        if (root == "" && child == "") {
          return const SizedBox.shrink(); // nothing selected yet
        }

        final textTheme = Theme.of(context).textTheme;
        final accent = Theme.of(context).colorScheme.secondary;

        return Column(
          children: [
            Text(
              root,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
            ...[
              const SizedBox(height: 2),
              Text(
                child,
                style: textTheme.bodyMedium?.copyWith(
                  color: textTheme.bodyMedium?.color?.withOpacity(0.85),
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
              ),
            ],
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: accent.withOpacity(0.18),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
                semanticsLabel: 'Goal progress',
              ),
            ),
          ],
        );
      },
    );
  }
}
