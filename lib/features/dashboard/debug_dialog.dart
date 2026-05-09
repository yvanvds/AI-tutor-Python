import 'dart:convert';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebugDialog extends ConsumerStatefulWidget {
  const DebugDialog({super.key});

  @override
  ConsumerState<DebugDialog> createState() => _DebugDialogState();
}

class _DebugDialogState extends ConsumerState<DebugDialog> {
  QuestionDifficulty _difficulty = QuestionDifficulty.medium;
  bool _busy = false;

  static const List<(ChatRequestType, String)> _questionTypes = [
    (ChatRequestType.socraticQuestion, 'Socratic'),
    (ChatRequestType.mcQuestion, 'Multiple choice'),
    (ChatRequestType.explainCodeQuestion, 'Explain code'),
    (ChatRequestType.completeCodeQuestion, 'Complete code'),
    (ChatRequestType.writeCodeQuestion, 'Write code'),
  ];

  Future<void> _wipeProgress() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe progress?'),
        content: const Text(
          'This deletes progress, progress_history, lo_beliefs and '
          'turn_history docs for the signed-in user, and resets the '
          'account calibration to medium. Cannot be undone.',
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
      await ref.read(progressServiceProvider).deleteAllForCurrentUser();
      await ref.read(loBeliefsServiceProvider).deleteAllForCurrentUser();
      await ref.read(turnHistoryServiceProvider).deleteAllForCurrentUser();
      await ref
          .read(accountServiceProvider.notifier)
          .setCalibration(StudentCalibration.fresh());
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
    // Ad-hoc plan for debug-fired questions: no LO targeting, just the
    // chosen difficulty.
    final plan = QuestionPlan(
      type: type,
      difficulty: _difficulty,
      targetLOs: const [],
      reason: const TurnSelectionReason(
        candidateLOs: [],
        chosenReason: 'debug dialog',
        notchDropFired: false,
      ),
    );
    await ref.read(tutorServiceProvider.notifier).queryTutor(
      type: type,
      plan: plan,
    );
  }

  void _triggerLevelUp() {
    Navigator.of(context).pop();
    ref.read(levelUpControllerProvider.notifier).push(
      const LevelUpEvent(
        newLevel: 5,
        xpAwarded: 20,
        conceptName: 'elif-ladder',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorder = ref.read(debugServiceProvider);
    return AlertDialog(
      title: const Text('Debug'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _wipeProgress,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Wipe all progress (Azure)'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _triggerLevelUp,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Show level-up overlay'),
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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Recent turns',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: _RecentTurnsList(turns: recorder.buffer),
            ),
            ],
          ),
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

class _RecentTurnsList extends StatelessWidget {
  const _RecentTurnsList({required this.turns});

  final List<TurnRecord> turns;

  @override
  Widget build(BuildContext context) {
    if (turns.isEmpty) {
      return const Center(child: Text('No turns recorded yet.'));
    }
    final reversed = turns.reversed.toList(growable: false);
    return ListView.separated(
      itemCount: reversed.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = reversed[i];
        final p = t.persisted;
        final fallback = p?.hadFallback == true;
        final reason = p?.selectionReason;
        final isFu = p?.isFollowUp == true;
        final hasFu = t.followUp != null;
        final events = p?.signalEvents ?? const <TurnSignalEvent>[];
        final eventsLabel = events
            .map((e) =>
                '${e.kind.name}/${e.severity.name}')
            .join(', ');
        return ListTile(
          dense: true,
          tileColor: fallback
              ? Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.4)
              : null,
          title: Row(
            children: [
              if (isFu)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FU d=${p?.chainDepth ?? 0}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  '#${t.turnId}  ${t.requestType}'
                  '${p == null ? '' : '  → ${p.overallQuality.name}'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            [
              if (reason != null) reason.chosenReason,
              if (reason?.notchDropFired == true) 'notch-dropped',
              if (p != null) 'targets: ${p.targetLOIds.join(", ")}',
              if (p != null)
                'cal: ${p.calibrationBefore.name}→${p.calibrationAfter.name}',
              if (fallback) 'FALLBACK',
              if (hasFu) 'followUp: "${t.followUp!.question}"',
              if (events.isNotEmpty) 'events: $eventsLabel',
            ].whereType<String>().join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _showTurnDetail(ctx, t),
        );
      },
    );
  }

  void _showTurnDetail(BuildContext ctx, TurnRecord t) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text('Turn #${t.turnId}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(t.toJson()),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
