import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';

class GoalTile extends StatelessWidget {
  final Goal goal;
  final Goal? rootGoal;
  final double progress;
  final int depth;
  final bool isSubgoal;

  const GoalTile({
    super.key,
    required this.goal,
    required this.rootGoal,
    required this.progress,
    required this.depth,
    required this.isSubgoal,
  });

  @override
  Widget build(BuildContext context) {
    final indent = depth * 16.0;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12),
      child: Card(
        elevation: isSubgoal ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + optional button
              Row(
                children: [
                  Expanded(
                    child: Text(goal.title, style: theme.textTheme.titleMedium),
                  ),
                  if (isSubgoal && progress < 1.0)
                    ElevatedButton.icon(
                      onPressed: () async {
                        final newProgress = (progress + 0.1).clamp(0.0, 1.0);
                        await DataService.progress.upsert(
                          Progress(goalID: goal.id, progress: newProgress),
                        );
                        DataService.progress.currentProgress.value =
                            newProgress;
                      },
                      icon: const Icon(Icons.fast_forward),
                      label: const Text('Ga sneller'),
                    ),
                  if (isSubgoal)
                    ElevatedButton.icon(
                      onPressed: () async {
                        DataService.goals.preferredChildGoal.value = goal;
                        DataService.goals.preferredRootGoal.value = rootGoal;

                        if (progress >= 1.0) {
                          await DataService.progress.upsert(
                            Progress(goalID: goal.id, progress: 0.5),
                          );
                          DataService.progress.currentProgress.value = 0.5;
                        } else {
                          DataService.progress.currentProgress.value = progress;
                        }

                        DataService.tutor.initializeSession(force: true);
                      },
                      label: const Text('Werk hieraan'),
                      icon: const Icon(Icons.play_arrow),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                    ),
                ],
              ),

              // Description
              if (goal.description != null &&
                  goal.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: Text(
                    goal.description!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),

              // Progress bar + %
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
