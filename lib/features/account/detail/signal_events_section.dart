// "Signaaleventjes" section in the teacher detail drawer.
// Renders strong (badge-driving) and audit-only events from `turn_history`
// for one student per CONDUCTOR_POLICY §8.2. The "Bevestigen" action clears
// every currently-listed strong-event acknowledgment for this student.

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SignalEventsSection extends ConsumerStatefulWidget {
  const SignalEventsSection({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<SignalEventsSection> createState() =>
      _SignalEventsSectionState();
}

class _SignalEventsSectionState extends ConsumerState<SignalEventsSection> {
  bool _ackBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.drawer_signals_title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              StreamBuilder<int>(
                stream: ref
                    .read(turnHistoryServiceProvider)
                    .watchStrongUnacknowledgedFor(widget.uid),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  return TextButton(
                    onPressed: (n == 0 || _ackBusy)
                        ? null
                        : () => _acknowledge(context),
                    child: Text(_ackBusy
                        ? l.drawer_signals_button_busy
                        : l.drawer_signals_button_acknowledge(n)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<List<PersistedTurnRecord>>(
            stream: ref
                .read(turnHistoryServiceProvider)
                .watchEventsFor(widget.uid),
            builder: (context, snap) {
              final records = snap.data ?? const <PersistedTurnRecord>[];
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              if (records.isEmpty) {
                return Text(
                  l.drawer_signals_empty,
                  style: theme.textTheme.bodySmall,
                );
              }
              // Strong first, then audit; preserve newest-first within group.
              final strong = <_EventRow>[];
              final audit = <_EventRow>[];
              for (final r in records) {
                for (final e in r.signalEvents) {
                  final row = _EventRow(record: r, event: e);
                  if (e.severity == TurnSignalEventSeverity.strong) {
                    strong.add(row);
                  } else {
                    audit.add(row);
                  }
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in strong) _renderRow(theme, l, row),
                  if (strong.isNotEmpty && audit.isNotEmpty)
                    const Divider(height: 12),
                  for (final row in audit) _renderRow(theme, l, row),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _renderRow(ThemeData theme, AppLocalizations l, _EventRow row) {
    final isStrong = row.event.severity == TurnSignalEventSeverity.strong;
    final ack = row.record.acknowledgedAt != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ack
                  ? Colors.grey.shade400
                  : (isStrong
                      ? Colors.red.shade400
                      : Colors.amber.shade600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kindLabel(l, row.event.kind),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: ack ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${formatTs(row.record.turnAt)}'
                  '${_detailSummary(row.event.details)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(AppLocalizations l, TurnSignalEventKind kind) {
    switch (kind) {
      case TurnSignalEventKind.stuckLoAdvance:
        return l.drawer_signals_kind_stuckLoAdvance;
      case TurnSignalEventKind.singleLoDeadlock:
        return l.drawer_signals_kind_singleLoDeadlock;
      case TurnSignalEventKind.repeatedDemotions:
        return l.drawer_signals_kind_repeatedDemotions;
      case TurnSignalEventKind.sustainedLlmFailure:
        return l.drawer_signals_kind_sustainedLlmFailure;
      case TurnSignalEventKind.cascadeHalt:
        return l.drawer_signals_kind_cascadeHalt;
      case TurnSignalEventKind.emptyObjectivesBlock:
        return l.drawer_signals_kind_emptyObjectivesBlock;
      case TurnSignalEventKind.subgoalDeletedRedirect:
        return l.drawer_signals_kind_subgoalDeletedRedirect;
    }
  }

  String _detailSummary(Map<String, Object?> details) {
    if (details.isEmpty) return '';
    final entries = details.entries.take(2).map((e) {
      final v = e.value;
      final rendered = v is List ? v.join(', ') : v?.toString() ?? '';
      return '${e.key}: $rendered';
    }).join(' · ');
    return ' — $entries';
  }

  Future<void> _acknowledge(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _ackBusy = true);
    try {
      await ref
          .read(turnHistoryServiceProvider)
          .acknowledgeAllFor(widget.uid);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.drawer_signals_ackFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _ackBusy = false);
    }
  }
}

class _EventRow {
  final PersistedTurnRecord record;
  final TurnSignalEvent event;
  _EventRow({required this.record, required this.event});
}
