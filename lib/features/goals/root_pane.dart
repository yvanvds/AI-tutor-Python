import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/widgets/add_input.dart';
import 'package:flutter/material.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'root_row.dart';

class RootPane extends StatelessWidget {
  const RootPane({
    super.key,
    required this.rootsAsync,
    required this.selectedRootId,
  });

  final Stream<List<Goal>> rootsAsync;
  final String? selectedRootId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add root goal… (Enter)',
            onSubmit: (t) => DataService.goals.createRoot(t),
          ),
        ),

        Expanded(
          child: StreamBuilder<List<Goal>>(
            stream: rootsAsync,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (snapshot.hasData) {
                final roots = snapshot.data!;
                // auto-select first
                if (selectedRootId == null && roots.isNotEmpty) {
                  Future.microtask(
                    () =>
                        DataService.goals.selectedRootGoal.value = roots.first,
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
                    await DataService.goals.applyOrder(
                      null,
                      list.map((g) => g.id).toList(),
                    );
                    final messenger = ScaffoldMessenger.of(context);

                    showUndoSnackBar(
                      messenger,
                      message: 'Reordered "${item.title}".',
                      onUndo: () async => await DataService.goals.applyOrder(
                        null,
                        before.map((g) => g.id).toList(),
                      ),
                    );
                  },

                  itemCount: roots.length,
                  itemBuilder: (_, i) {
                    final g = roots[i];
                    final selected =
                        g.id == DataService.goals.selectedRootGoal.value?.id;
                    return RootRow(
                      key: ValueKey(g.id),
                      goal: g,
                      selected: selected,
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
