import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dnd.dart';
import 'drag_feedback.dart';

class ChildRow extends ConsumerWidget {
  const ChildRow({
    super.key,
    required this.goal,
    required this.selectedRootId,
    required this.index,
  });

  final Goal goal;
  final String? selectedRootId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<GoalDragData>(
      key: ValueKey('child_${goal.id}'),
      data: GoalDragData(goalId: goal.id, fromParentId: selectedRootId),
      feedback: dragFeedback(context, goal.title),
      child: ListTile(
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
          ref.read(goalSelectionProvider.notifier).setEditorSelectedGoal(goal);
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
