import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:ai_tutor_python/widgets/add_input.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'root_row.dart';

class RootPane extends ConsumerWidget {
  const RootPane({
    super.key,
    required this.repo,
    required this.rootsAsync,
    required this.selectedRootId,
  });

  final GoalsRepository repo;
  final AsyncValue<List<Goal>> rootsAsync;
  final String? selectedRootId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add root goal… (Enter)',
            onSubmit: (t) => repo.createRoot(t),
          ),
        ),

        Expanded(
          child: rootsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (roots) {
              // auto-select first
              if (selectedRootId == null && roots.isNotEmpty) {
                Future.microtask(
                  () => ref
                      .read(selectedRootGoalProviderNotifier.notifier)
                      .select(roots.first.id),
                );
              }
              if (roots.isEmpty) {
                return const Center(
                  child: Text('No goals yet. Add one above.'),
                );
              }

              // --- Reorder roots
              return ReorderableListView.builder(
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) async {
                  final before = [...roots];
                  var list = [...roots];
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = list.removeAt(oldIndex);
                  list.insert(newIndex, item);
                  await repo.applyOrder(null, list.map((g) => g.id).toList());
                  final messenger = ScaffoldMessenger.of(context);

                  showUndoSnackBar(
                    messenger,
                    message: 'Reordered "${item.title}".',
                    onUndo: () async =>
                        repo.applyOrder(null, before.map((g) => g.id).toList()),
                  );
                },

                itemCount: roots.length,
                itemBuilder: (_, i) {
                  final g = roots[i];
                  final selected =
                      g.id == ref.watch(selectedRootGoalProviderNotifier);
                  return RootRow(
                    key: ValueKey(g.id),
                    goal: g,
                    selected: selected,
                    index: i,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
