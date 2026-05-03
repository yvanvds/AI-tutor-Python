import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/widgets/add_input.dart';
import 'package:flutter/material.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'root_row.dart';

class RootPane extends ConsumerWidget {
  const RootPane({super.key, required this.rootsAsync});

  final Stream<List<Goal>> rootsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRoot = ref.watch(goalSelectionProvider).editorSelectedRoot;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: AddInput(
            hint: 'Add root goal… (Enter)',
            onSubmit: (t) => ref.read(goalsServiceProvider).createRoot(t),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Goal>>(
            stream: rootsAsync,
            builder: (context, snapshot) =>
                _buildRootsList(context, snapshot, selectedRoot, ref),
          ),
        ),
      ],
    );
  }

  Widget _buildRootsList(
    BuildContext context,
    AsyncSnapshot<List<Goal>> snapshot,
    Goal? selectedRoot,
    WidgetRef ref,
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
    if (selectedRoot == null && roots.isNotEmpty) {
      Future.microtask(() {
        ref.read(goalSelectionProvider.notifier).setEditorSelectedRoot(
          roots.first,
        );
        ref.read(goalSelectionProvider.notifier).setEditorSelectedGoal(
          roots.first,
        );
      });
    }
    if (roots.isEmpty) {
      return const Center(child: Text('No goals yet. Add one above.'));
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          _onReorder(context, roots, oldIndex, newIndex, ref),
      itemCount: roots.length,
      itemBuilder: (_, i) {
        final g = roots[i];
        return RootRow(
          key: ValueKey(g.id),
          goal: g,
          selected: g.id == selectedRoot?.id,
          index: i,
        );
      },
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    List<Goal> roots,
    int oldIndex,
    int newIndex,
    WidgetRef ref,
  ) async {
    final before = [...roots];
    final list = [...roots];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final messenger = ScaffoldMessenger.of(context);
    final svc = ref.read(goalsServiceProvider);
    await svc.applyOrder(null, list.map((g) => g.id).toList());

    showUndoSnackBar(
      messenger,
      message: 'Reordered "${item.title}".',
      onUndo: () async =>
          svc.applyOrder(null, before.map((g) => g.id).toList()),
    );
  }
}
