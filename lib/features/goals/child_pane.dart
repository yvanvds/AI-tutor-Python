import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../widgets/add_input.dart';
import 'child_row.dart';

class ChildPane extends ConsumerWidget {
  const ChildPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRootId = ref.watch(selectedRootGoalProviderNotifier);
    final repo = ref.watch(goalsRepositoryProvider);
    if (selectedRootId == null) {
      return const Center(
        child: Text('Select a root goal to see its children.'),
      );
    }

    final childrenAsync = ref.watch(childGoalsProviderStream);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add child goal… (Enter)',
            onSubmit: (t) => repo.createChild(selectedRootId, t),
          ),
        ),
        Expanded(
          child: childrenAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (children) {
              if (children.isEmpty) {
                return const Center(
                  child: Text('No children yet. Add one above.'),
                );
              }
              // Reorder within the selected parent
              return ReorderableListView.builder(
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) async {
                  final before = [...children]; // snapshot for undo
                  var list = [...children];
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = list.removeAt(oldIndex);
                  list.insert(newIndex, item);
                  await repo.applyOrder(
                    selectedRootId,
                    list.map((g) => g.id).toList(),
                  );

                  final messenger = ScaffoldMessenger.of(context);

                  showUndoSnackBar(
                    messenger,
                    message: 'Reordered "${item.title}".',
                    onUndo: () async => repo.applyOrder(
                      selectedRootId,
                      before.map((g) => g.id).toList(),
                    ),
                  );
                },

                itemCount: children.length,
                itemBuilder: (_, i) {
                  final c = children[i];

                  // Make a child draggable across panes
                  return ChildRow(
                    key: ValueKey('child_${c.id}'),
                    goal: c,
                    selectedRootId: selectedRootId,
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
