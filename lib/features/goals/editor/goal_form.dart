import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/goal/goals_repository.dart';
import 'package:ai_tutor_python/features/goals/editor/parent_field.dart';
import 'package:ai_tutor_python/widgets/chips_editor.dart';
import 'package:ai_tutor_python/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({required this.goal, required this.repo});
  final Goal goal;
  final GoalsRepository repo;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit goal'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(
                context,
              ); // <-- capture BEFORE awaits/closing
              final repo = widget.repo;
              final id = widget.goal.id;

              // Count children for safety messaging
              final count = await repo.countDescendants(id);
              final confirmed =
                  await showDialog<bool>(
                    context: context,
                    builder: (dCtx) {
                      return AlertDialog(
                        title: const Text('Delete goal'),
                        content: Text(
                          count == 0
                              ? 'Delete “${widget.goal.title}”?'
                              : 'Delete “${widget.goal.title}” and its $count descendant(s)?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                    },
                  ) ??
                  false;

              if (!confirmed) return;

              // Backup → delete → Undo
              final backup = await repo.backupSubtree(id);
              await repo.deleteSubtree(id);

              // Close the editor if we just deleted the opened node
              if (mounted) {
                ref.read(editingGoalIdProviderNotifier.notifier).close();
              }

              showUndoSnackBar(
                messenger,
                message: count == 0
                    ? 'Deleted "${widget.goal.title}".'
                    : 'Deleted "${widget.goal.title}" (+$count).',
                onUndo: () async {
                  await repo.restoreSubtree(backup);
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () =>
                ref.read(editingGoalIdProviderNotifier.notifier).close(),
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
            onSubmitted: (t) => widget.repo.updateTitle(
              widget.goal.id,
              t.trim().isEmpty ? 'Untitled' : t.trim(),
            ),
            onChanged:
                (
                  t,
                ) {}, // explicit save on submit; we already have inline title elsewhere
          ),
          const SizedBox(height: 12),
          widget.goal.parentId != null
              ? ParentField(goal: widget.goal, repo: widget.repo)
              : const SizedBox.shrink(),
          const SizedBox(height: 12),

          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Describe this goal for students.',
              border: OutlineInputBorder(),
            ),
            onChanged: (t) => widget.repo.updateDescription(
              widget.goal.id,
              t.isEmpty ? null : t,
            ),
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            value: _optional,
            onChanged: (v) {
              setState(() => _optional = v);
              widget.repo.updateOptional(widget.goal.id, v);
            },
            title: const Text('Optional'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),

          ChipsEditor(
            label: 'Suggestions',
            values: widget.goal.suggestions,
            hintText: 'Type a suggestion and hit Enter',
            onChanged: (vals) =>
                widget.repo.updateSuggestions(widget.goal.id, vals),
          ),
        ],
      ),
    );
  }
}
