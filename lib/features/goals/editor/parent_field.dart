import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ParentField extends ConsumerWidget {
  const ParentField({super.key, required this.goal, required this.repo});
  final Goal goal;
  final GoalsRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only roots in the parent dropdown
    final rootsAsync = ref.watch(rootGoalsProviderStream);

    Widget result;
    result = rootsAsync.when(
      loading: () => const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text('Failed to load parents: $e'),
      data: (roots) {
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('(no parent)'),
          ),
          ...roots.map(
            (g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.title)),
          ),
        ];
        return DropdownButtonFormField<String?>(
          value: goal.parentId, // may be null
          items: items,
          onChanged: (newParent) async {
            if (newParent == goal.parentId) return;
            await repo.reparent(goal.id, newParent);
          },
          decoration: const InputDecoration(
            labelText: 'Parent',
            border: OutlineInputBorder(),
          ),
        );
      },
    );

    return result;
  }
}
