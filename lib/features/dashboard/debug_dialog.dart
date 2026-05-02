import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

class DebugDialog extends StatefulWidget {
  const DebugDialog({super.key});

  @override
  State<DebugDialog> createState() => _DebugDialogState();
}

class _DebugDialogState extends State<DebugDialog> {
  QuestionDifficulty _difficulty = QuestionDifficulty.easy;
  bool _busy = false;

  static const List<(ChatRequestType, String)> _questionTypes = [
    (ChatRequestType.socraticQuestion, 'Socratic'),
    (ChatRequestType.mcQuestion, 'Multiple choice'),
    (ChatRequestType.explainCodeQuestion, 'Explain code'),
    (ChatRequestType.completeCodeQuestion, 'Complete code'),
    (ChatRequestType.writeCodeQuestion, 'Write code'),
    (ChatRequestType.guidingQuestion, 'Guiding'),
  ];

  Future<void> _wipeProgress() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe progress?'),
        content: const Text(
          'This deletes every progress and progress_history doc for the '
          'signed-in user from Cosmos. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Wipe'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await DataService.progress.deleteAllForCurrentUser();
      messenger.showSnackBar(
        const SnackBar(content: Text('Progress wiped.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Wipe failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _triggerQuestion(ChatRequestType type) async {
    Navigator.of(context).pop();
    final needsDifficulty = type != ChatRequestType.guidingQuestion;
    await DataService.tutor.queryTutor(
      type: type,
      difficulty: needsDifficulty ? _difficulty : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Debug'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _wipeProgress,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Wipe all progress (Azure)'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Trigger question',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Difficulty:'),
                const SizedBox(width: 12),
                DropdownButton<QuestionDifficulty>(
                  value: _difficulty,
                  onChanged: (v) {
                    if (v != null) setState(() => _difficulty = v);
                  },
                  items: QuestionDifficulty.values
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.name),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (type, label) in _questionTypes)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _triggerQuestion(type),
                    child: Text(label),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
