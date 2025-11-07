import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter/material.dart';
import 'goal_form.dart';

class EditGoalPanel extends StatelessWidget {
  const EditGoalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final editingId = DataService.goals.editorSelectedGoal.value?.id;
    Stream<Goal?>? goalAsync;
    if (editingId != null) {
      goalAsync = DataService.goals.streamGoal(editingId);
    }

    final isOpen = editingId != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: isOpen ? 420 : 0,
      decoration: BoxDecoration(
        border: isOpen
            ? Border(left: BorderSide(color: Theme.of(context).dividerColor))
            : null,
        color: Theme.of(context).colorScheme.surface,
      ),
      child: isOpen
          ? StreamBuilder<Goal?>(
              stream: goalAsync,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error loading documents: ${snapshot.error}'),
                    ),
                  );
                }
                final goal = snapshot.data;

                if (goal == null) {
                  return const Center(child: Text('No goal selected.'));
                }
                return GoalForm(goal: goal);
              },
            )
          : const SizedBox.shrink(),
    );
  }
}
