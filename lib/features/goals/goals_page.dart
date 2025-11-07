import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

import 'child_pane.dart';
import 'editor/edit_goal_panel.dart';
import 'root_pane.dart';

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rootsAsync = DataService.goals.streamRoots!;
    final selectedRootId = DataService.goals.editorSelectedRootGoal.value?.id;

    return Row(
      children: [
        // LEFT: Roots + root drop zone
        Expanded(
          child: RootPane(
            rootsAsync: rootsAsync,
            selectedRootId: selectedRootId,
          ),
        ),

        const VerticalDivider(width: 1),

        // RIGHT: Children of selected root
        Expanded(child: ChildPane()),
        const VerticalDivider(width: 1),

        SizedBox(width: 720, child: const EditGoalPanel()),
      ],
    );
  }
}
