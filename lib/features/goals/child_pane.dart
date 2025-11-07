import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import '../../widgets/add_input.dart';
import 'child_row.dart';

class ChildPane extends StatelessWidget {
  const ChildPane({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedRootId = DataService.goals.editorSelectedRootGoal.value?.id;

    if (selectedRootId == null) {
      return const Center(
        child: Text('Select a root goal to see its children.'),
      );
    }

    final childrenAsync = DataService.goals.streamChildren(selectedRootId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add child goal… (Enter)',
            onSubmit: (t) => DataService.goals.createChild(selectedRootId, t),
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
                // Reorder within the selected parent
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) async {
                    final before = [...children]; // snapshot for undo
                    var list = [...children];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    await DataService.goals.applyOrder(
                      selectedRootId,
                      list.map((g) => g.id).toList(),
                    );

                    final messenger = ScaffoldMessenger.of(context);

                    showUndoSnackBar(
                      messenger,
                      message: 'Reordered "${item.title}".',
                      onUndo: () async => DataService.goals.applyOrder(
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
