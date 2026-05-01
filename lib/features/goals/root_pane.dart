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
  });

  final Stream<List<Goal>> rootsAsync;

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
            builder: _buildRootsList,
          ),
        ),
      ],
    );
  }

  Widget _buildRootsList(
    BuildContext context,
    AsyncSnapshot<List<Goal>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(child: Text('Error: ${snapshot.error}'));
    }
    if (!snapshot.hasData) {
      return const Center(child: Text('No data'));
    }

    final roots = snapshot.data!;
    if (DataService.goals.editorSelectedRootGoal.value == null &&
        roots.isNotEmpty) {
      Future.microtask(() {
        DataService.goals.editorSelectedRootGoal.value = roots.first;
        DataService.goals.editorSelectedGoal.value = roots.first;
      });
    }
    if (roots.isEmpty) {
      return const Center(child: Text('No goals yet. Add one above.'));
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          _onReorder(context, roots, oldIndex, newIndex),
      itemCount: roots.length,
      itemBuilder: (_, i) {
        final g = roots[i];
        return ValueListenableBuilder<Goal?>(
          key: ValueKey(g.id),
          valueListenable: DataService.goals.editorSelectedRootGoal,
          builder: (_, sel, _) => RootRow(
            goal: g,
            selected: g.id == sel?.id,
            index: i,
          ),
        );
      },
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    List<Goal> roots,
    int oldIndex,
    int newIndex,
  ) async {
    final before = [...roots];
    final list = [...roots];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final messenger = ScaffoldMessenger.of(context);
    await DataService.goals.applyOrder(
      null,
      list.map((g) => g.id).toList(),
    );

    showUndoSnackBar(
      messenger,
      message: 'Reordered "${item.title}".',
      onUndo: () async => await DataService.goals.applyOrder(
        null,
        before.map((g) => g.id).toList(),
      ),
    );
  }
}
