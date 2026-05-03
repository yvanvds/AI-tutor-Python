import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GoalCrumbInAppBar extends ConsumerWidget {
  const GoalCrumbInAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(goalSelectionProvider);
    final progress = ref.watch(currentProgressProvider);

    final root = selection.activeRootGoal?.title ?? '';
    final child = selection.activeChildGoal?.title ?? '';

    if (root.isEmpty && child.isEmpty) return const SizedBox.shrink();

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
        const SizedBox(height: 2),
        Text(
          child,
          style: textTheme.bodyMedium?.copyWith(
            color: textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
            overflow: TextOverflow.ellipsis,
          ),
          maxLines: 1,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: accent.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            semanticsLabel: 'Goal progress',
          ),
        ),
      ],
    );
  }
}
