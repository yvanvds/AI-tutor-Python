import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dnd.dart';
import 'drag_feedback.dart';

class RootRow extends ConsumerWidget {
  const RootRow({
    super.key,
    required this.goal,
    required this.selected,
    required this.index,
  });
  final Goal goal;
  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Each root row is draggable (to reorder within roots).
    return LongPressDraggable<GoalDragData>(
      data: GoalDragData(goalId: goal.id, fromParentId: null),
      feedback: DragFeedback(context, goal.title),

      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest,
        title: Text(goal.title, style: const TextStyle(fontSize: 18)),
        subtitle: Text(
          goal.optional ? '(Optional)' : '',
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: 12,
            color: Colors.indigoAccent,
          ),
        ),
        onTap: () {
          ref.read(selectedRootGoalProviderNotifier.notifier).select(goal.id);
          ref.read(editingGoalIdProviderNotifier.notifier).open(goal.id);
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }
}
