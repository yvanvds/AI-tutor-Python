import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/features/goals/editor/parent_field.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
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
          if (widget.goal.parentId != null) ...[
            ChipsEditor(
              label: 'Teaching tips',
              values: widget.goal.teachingTips,
              hintText: 'Type a teaching tip and hit Enter',
              onChanged: (vals) =>
                  svc.updateTeachingTips(widget.goal.id, vals),
            ),
            const SizedBox(height: 12),
            _LesinhoudRow(goal: widget.goal),
            const SizedBox(height: 12),
          ],
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

/// Inline status row in the subgoal editor: shows whether the subgoal has
/// authored content, with a one-click handoff to the Lesinhoud view.
class _LesinhoudRow extends ConsumerWidget {
  const _LesinhoudRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cid = goal.contentId;
    final hasContent = cid != null && cid.isNotEmpty;
    final cached = ref.watch(contentServiceProvider);
    final title = hasContent
        ? cached
            .where((c) => c.id == cid)
            .map((c) => c.title)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null)
        : null;

    void openInLesinhoud() {
      ref.read(pendingLessonContentGoalIdProvider.notifier).state = goal.id;
      ref.read(sectionProvider.notifier).state = Section.lessonContent;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            hasContent ? Icons.article_outlined : Icons.article_outlined,
            size: 16,
            color: hasContent
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lesinhoud',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Text(
                  hasContent
                      ? (title ?? 'Lesinhoud gekoppeld')
                      : '(geen lesinhoud)',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasContent ? null : Theme.of(context).disabledColor,
                    fontStyle:
                        hasContent ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: openInLesinhoud,
            child: Text(hasContent ? 'Bewerk' : 'Maak'),
          ),
        ],
      ),
    );
  }
}
