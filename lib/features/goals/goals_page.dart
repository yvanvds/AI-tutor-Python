import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'child_pane.dart';
import 'editor/edit_goal_panel.dart';
import 'root_pane.dart';

class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootsAsync = ref.watch(rootGoalsProviderStream);
    final selectedRootId = ref.watch(selectedRootGoalProviderNotifier);
    final repo = ref.watch(goalsRepositoryProvider);

    return Row(
      children: [
        // LEFT: Roots + root drop zone
        Expanded(
          child: RootPane(
            repo: repo,
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
