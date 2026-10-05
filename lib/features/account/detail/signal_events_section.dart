// "Signaaleventjes" section in the teacher detail drawer.
// Renders strong (badge-driving) and audit-only events from `turn_history`
// for one student per CONDUCTOR_POLICY §8.2. The "Bevestigen" action clears
// every currently-listed strong-event acknowledgment for this student.

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/no_progress.dart';
import 'package:ai_tutor_python/services/supervision/provenance_gap.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SignalEventsSection extends ConsumerStatefulWidget {
  const SignalEventsSection({
    super.key,
    required this.uid,
    this.goals = const [],
  });

  final String uid;

  /// The curriculum, to name an event's LO by its statement and its subgoal
  /// by its title rather than their ids (#107, #229). One it does not hold
  /// is shown by its id.
  final List<Goal> goals;

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
                    child: Text(
                      _ackBusy
                          ? l.drawer_signals_button_busy
                          : l.drawer_signals_button_acknowledge(n),
                    ),
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
    final ts = formatTs(row.record.turnAt, context);
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
                  : (isStrong ? Colors.red.shade400 : Colors.amber.shade600),
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
                  '$ts${_detailLine(l, row.event)}',
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
      case TurnSignalEventKind.noProgress:
        return l.drawer_signals_kind_noProgress;
      case TurnSignalEventKind.cascadeHalt:
        return l.drawer_signals_kind_cascadeHalt;
      case TurnSignalEventKind.emptyObjectivesBlock:
        return l.drawer_signals_kind_emptyObjectivesBlock;
      case TurnSignalEventKind.subgoalDeletedRedirect:
        return l.drawer_signals_kind_subgoalDeletedRedirect;
      case TurnSignalEventKind.targetSignalLost:
        return l.drawer_signals_kind_targetSignalLost;
      case TurnSignalEventKind.provenanceGap:
        return l.drawer_signals_kind_provenanceGap;
    }
  }

  /// What follows the timestamp: for a provenance gap (#107) the LO and the
  /// two counts in words; for a stuck student (#229) the subgoal, since
  /// when, the answers not right and the LO asked most; for a run of lost
  /// grades (#229) how many and on which LO; for every other kind the first
  /// details.
  String _detailLine(AppLocalizations l, TurnSignalEvent event) {
    final stuck = NoProgress.fromEvent(event);
    if (stuck != null) return ' — ${_noProgressLine(l, stuck)}';
    final run = _lostRun(event);
    if (run != null) {
      final text = l.drawer_signals_targetSignalLost_run_detail(
        run.count,
        _loStatement(run.subgoalId, run.loId),
      );
      return ' — $text';
    }
    final gap = ProvenanceGap.fromEvent(event);
    if (gap == null) return _detailSummary(event.details);
    final days = switch (event.details['windowDays']) {
      final num n => n.toInt(),
      _ => PolicyConstants.provenanceGapWindow.inDays,
    };
    final text = l.drawer_signals_provenanceGap_detail(
      _loStatement(gap.subgoalId, gap.loId),
      gap.homePositive,
      gap.homeSignals,
      gap.supervisedPositive,
      gap.supervisedSignals,
      days,
    );
    return ' — $text';
  }

  String _noProgressLine(AppLocalizations l, NoProgress stuck) {
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final line = l.drawer_signals_noProgress_detail(
      _subgoalTitle(stuck.subgoalId),
      DateFormat.Hm(localeTag).format(stuck.since.toLocal()),
      stuck.minutes,
      stuck.notRight,
      stuck.answers,
    );
    final loId = stuck.loId;
    final mean = stuck.mean;
    if (loId == null || mean == null) return line;
    final mostAsked = l.drawer_signals_noProgress_mostAsked(
      _loStatement(stuck.subgoalId, loId),
      NumberFormat('0.00', localeTag).format(mean),
    );
    return '$line, $mostAsked';
  }

  /// The run of a strong `targetSignalLost` event (#229): how many direct
  /// questions in a row, and the last one's LO. `null` for an audit one, or
  /// another kind.
  static ({int count, String subgoalId, String loId})? _lostRun(
    TurnSignalEvent event,
  ) {
    if (event.kind != TurnSignalEventKind.targetSignalLost ||
        event.severity != TurnSignalEventSeverity.strong) {
      return null;
    }
    final d = event.details;
    final count = d['run'];
    final subgoalId = d['subgoalId'];
    final loId = d['loId'];
    if (count is! num || subgoalId is! String || loId is! String) return null;
    return (count: count.toInt(), subgoalId: subgoalId, loId: loId);
  }

  String _subgoalTitle(String subgoalId) {
    for (final g in widget.goals) {
      if (g.id == subgoalId && g.title.trim().isNotEmpty) return g.title.trim();
    }
    return subgoalId;
  }

  String _loStatement(String subgoalId, String loId) {
    for (final g in widget.goals) {
      if (g.id != subgoalId) continue;
      for (final lo in g.objectives) {
        if (lo.id == loId && lo.statement.trim().isNotEmpty) {
          return lo.statement.trim();
        }
      }
    }
    return loId;
  }

  String _detailSummary(Map<String, Object?> details) {
    if (details.isEmpty) return '';
    final entries = details.entries
        .take(2)
        .map((e) {
          final v = e.value;
          final rendered = v is List ? v.join(', ') : v?.toString() ?? '';
          return '${e.key}: $rendered';
        })
        .join(' · ');
    return ' — $entries';
  }

  Future<void> _acknowledge(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _ackBusy = true);
    try {
      await ref.read(turnHistoryServiceProvider).acknowledgeAllFor(widget.uid);
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
