import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/add_input.dart';
import 'child_row.dart';

class ChildPane extends ConsumerWidget {
  const ChildPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoot =
        ref.watch(goalSelectionProvider).editorSelectedRoot;
    final selectedRootId = selectedRoot?.id;

    if (selectedRootId == null) {
      return const Center(
        child: Text('Select a root goal to see its children.'),
      );
    }

    return _buildList(
      context,
      selectedRootId,
      ref.read(goalsServiceProvider).streamChildren(selectedRootId),
      ref,
    );
  }

  Widget _buildList(
    BuildContext context,
    String selectedRootId,
    Stream<List<Goal>> childrenAsync,
    WidgetRef ref,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add child goal… (Enter)',
            onSubmit: (t) =>
                ref.read(goalsServiceProvider).createChild(selectedRootId, t),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Goal>>(
            stream: childrenAsync,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (snapshot.hasData) {
                final children = snapshot.data!;
                if (children.isEmpty) {
                  return const Center(
                    child: Text('No children yet. Add one above.'),
                  );
                }
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) async {
                    final before = [...children];
                    var list = [...children];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    final messenger = ScaffoldMessenger.of(context);
                    final svc = ref.read(goalsServiceProvider);
                    await svc.applyOrder(
                      selectedRootId,
                      list.map((g) => g.id).toList(),
                    );
                    showUndoSnackBar(
                      messenger,
                      message: 'Reordered "${item.title}".',
                      onUndo: () async => svc.applyOrder(
                        selectedRootId,
                        before.map((g) => g.id).toList(),
                      ),
                    );
                  },
                  itemCount: children.length,
                  itemBuilder: (_, i) {
                    final c = children[i];
                    return ChildRow(
                      key: ValueKey('child_${c.id}'),
                      goal: c,
                      selectedRootId: selectedRootId,
                      index: i,
                    );
                  },
                );
              } else {
                return const Center(child: Text('No data'));
              }
            },
          ),
        ),
      ],
    );
  }
}
