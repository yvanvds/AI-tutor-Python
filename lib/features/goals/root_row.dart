import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter/material.dart';
import 'dnd.dart';
import 'drag_feedback.dart';

class RootRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          DataService.goals.editorSelectedGoal.value = goal;
          DataService.goals.editorSelectedRootGoal.value = goal;
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
