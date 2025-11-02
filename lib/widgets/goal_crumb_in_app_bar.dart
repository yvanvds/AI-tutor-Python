import 'package:ai_tutor_python/data/goal/current_goal_display_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GoalCrumbInAppBar extends ConsumerWidget {
  const GoalCrumbInAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(currentGoalDisplayProvider);
    final root = vm.rootTitle;
    final child = vm.childTitle;
    final progress = (vm.progress ?? 0).clamp(0.0, 1.0);

    if (root == null && child == null) {
      return const SizedBox.shrink(); // nothing selected yet
    }

    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.secondary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (root != null)
            Text(
              root,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          if (child != null) ...[
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
      ),
    );
  }
}
