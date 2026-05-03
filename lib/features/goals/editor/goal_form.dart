import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/features/goals/editor/parent_field.dart';
import 'package:ai_tutor_python/widgets/chips_editor.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key, required this.goal});
  final Goal goal;

  @override
  ConsumerState<GoalForm> createState() => GoalFormState();
}

class GoalFormState extends ConsumerState<GoalForm> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  bool _optional = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.goal.title);
    _desc = TextEditingController(text: widget.goal.description ?? '');
    _optional = widget.goal.optional;
  }

  @override
  void didUpdateWidget(covariant GoalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goal.id != widget.goal.id) {
      _title.text = widget.goal.title;
      _desc.text = widget.goal.description ?? '';
      _optional = widget.goal.optional;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(goalsServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit goal'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete),
            onPressed: () => _handleDelete(context),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => ref
                .read(goalSelectionProvider.notifier)
                .setEditorSelectedGoal(null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (t) => svc.updateTitle(
              widget.goal.id,
              t.trim().isEmpty ? 'Untitled' : t.trim(),
            ),
            onChanged: (t) {},
          ),
          const SizedBox(height: 12),
          widget.goal.parentId != null
              ? ParentField(goal: widget.goal)
              : const SizedBox.shrink(),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Describe this goal for students.',
              border: OutlineInputBorder(),
            ),
            onChanged: (t) => svc.updateDescription(
              widget.goal.id,
              t.isEmpty ? null : t,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _optional,
            onChanged: (v) {
              setState(() => _optional = v);
              svc.updateOptional(widget.goal.id, v);
            },
            title: const Text('Optional'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          widget.goal.parentId != null
              ? ChipsEditor(
                  label: 'Suggestions',
                  values: widget.goal.suggestions,
                  hintText: 'Type a suggestion and hit Enter',
                  onChanged: (vals) =>
                      svc.updateSuggestions(widget.goal.id, vals),
                )
              : ChipsEditor(
                  label: 'Known Concepts After Completion',
                  values: widget.goal.knownConcepts,
                  hintText: 'Type a concept and hit Enter',
                  onChanged: (vals) =>
                      svc.updateKnownConcepts(widget.goal.id, vals),
                ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = widget.goal.id;
    final svc = ref.read(goalsServiceProvider);

    final count = await svc.countDescendants(id);
    if (!context.mounted) return;

    final confirmed = await _confirmDelete(context, count);
    if (!confirmed) return;

    final backup = await svc.backupSubtree(id);
    await svc.deleteSubtree(id);

    if (mounted) {
      ref
          .read(goalSelectionProvider.notifier)
          .setEditorSelectedGoal(null);
    }

    showUndoSnackBar(
      messenger,
      message: count == 0
          ? 'Deleted "${widget.goal.title}".'
          : 'Deleted "${widget.goal.title}" (+$count).',
      onUndo: () async => svc.restoreSubtree(backup),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          title: const Text('Delete goal'),
          content: Text(
            count == 0
                ? 'Delete "${widget.goal.title}"?'
                : 'Delete "${widget.goal.title}" and its $count descendant(s)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
