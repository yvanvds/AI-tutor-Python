// The passive supervised-vs-home check (#107, CONDUCTOR_POLICY §8.2,
// PUNTENFORMULE §2.7).
//
// Home credit counts in full at once and is confirmed — or contradicted — by
// later supervised work on the same LO. This check tells the teacher where it
// was clearly contradicted: per student, per LO, over
// [PolicyConstants.provenanceGapWindow], the direct signals of the home
// oefeningen were mostly positive and those of the supervised oefeningen
// after them mostly negative. A structural gap like that is what a chatbot
// at home looks like; it replaces routine spot-check tests.
//
// It is a signal for the teacher and nothing else: it writes no belief,
// changes no weight and no grade, and the student never sees it. It is an
// audit event (detail drawer, no badge) unless the gap is large and
// well-evidenced ([PolicyConstants.provenanceGapStrongMinSignals]).
//
// "Supervised" is read the way the grade proposal's tally reads it (#219):
// the turn was recorded `supervised`, or it falls in a lesson of the
// student's class — the turns graded before the timetable was the source are
// all `home` on the record.
//
// What a signal is: one entry of a graded turn's `appliedSignals` on one of
// that turn's target LOs (the question was about it — an ordinary question,
// a follow-up, a warm-up review or a recheck), not an incidental signal on
// another LO and not a transfer credit. Its direction is the sign of the
// belief delta `alphaDelta - betaDelta`; the size is left out — at the
// evidence cap a delta is mostly the shrink toward the prior (§3.4), and
// the supervised factor would make class answers look bigger. The check
// compares the share of positive signals on each side.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One direct signal on an LO: when, where, and which way it moved the
/// belief.
@immutable
class ProvenanceSignal {
  const ProvenanceSignal({
    required this.at,
    required this.supervised,
    required this.positive,
  });

  final DateTime at;
  final bool supervised;
  final bool positive;
}

/// A contradicted home credit on one LO: what the event carries.
@immutable
class ProvenanceGap {
  const ProvenanceGap({
    required this.subgoalId,
    required this.loId,
    required this.homeSignals,
    required this.homePositive,
    required this.supervisedSignals,
    required this.supervisedPositive,
    required this.severity,
  });

  final String subgoalId;
  final String loId;

  /// Direct home signals with supervised work on the LO after them, and how
  /// many of them were positive.
  final int homeSignals;
  final int homePositive;

  /// Direct supervised signals after the first of those home signals, and
  /// how many of them were positive.
  final int supervisedSignals;
  final int supervisedPositive;

  final TurnSignalEventSeverity severity;

  double get homeShare => homePositive / homeSignals;
  double get supervisedShare => supervisedPositive / supervisedSignals;

  TurnSignalEvent toEvent() => TurnSignalEvent(
    kind: TurnSignalEventKind.provenanceGap,
    severity: severity,
    details: {
      'subgoalId': subgoalId,
      'loId': loId,
      'homeSignals': homeSignals,
      'homePositive': homePositive,
      'supervisedSignals': supervisedSignals,
      'supervisedPositive': supervisedPositive,
      'windowDays': PolicyConstants.provenanceGapWindow.inDays,
    },
  );

  /// The gap a `provenanceGap` event describes, for the teacher's drawer;
  /// `null` for another kind or details it cannot read.
  static ProvenanceGap? fromEvent(TurnSignalEvent event) {
    if (event.kind != TurnSignalEventKind.provenanceGap) return null;
    final d = event.details;
    int? count(String key) => switch (d[key]) {
      final num n => n.toInt(),
      _ => null,
    };
    final subgoalId = d['subgoalId'];
    final loId = d['loId'];
    final homeSignals = count('homeSignals');
    final homePositive = count('homePositive');
    final supervisedSignals = count('supervisedSignals');
    final supervisedPositive = count('supervisedPositive');
    if (subgoalId is! String ||
        loId is! String ||
        homeSignals == null ||
        homePositive == null ||
        supervisedSignals == null ||
        supervisedPositive == null ||
        homeSignals <= 0 ||
        supervisedSignals <= 0) {
      return null;
    }
    return ProvenanceGap(
      subgoalId: subgoalId,
      loId: loId,
      homeSignals: homeSignals,
      homePositive: homePositive,
      supervisedSignals: supervisedSignals,
      supervisedPositive: supervisedPositive,
      severity: event.severity,
    );
  }
}

/// The direct signals on [loId] of [subgoalId] in [records], oldest first.
/// [supervised] is aligned with [records]. Audit records carry none; a
/// delta that moved neither way (at the cap, a positive on an LO already
/// at its ceiling) says nothing and is left out.
List<ProvenanceSignal> directSignalsOn({
  required String subgoalId,
  required String loId,
  required List<PersistedTurnRecord> records,
  required List<bool> supervised,
}) {
  final out = <ProvenanceSignal>[];
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    if (r.questionType.isEmpty || r.subgoalId != subgoalId) continue;
    if (!r.targetLOIds.contains(loId)) continue;
    for (final s in r.appliedSignals) {
      if (s.subgoalId != subgoalId || s.loId != loId) continue;
      final net = s.alphaDelta - s.betaDelta;
      if (net == 0) continue;
      out.add(
        ProvenanceSignal(
          at: r.turnAt,
          supervised: supervised[i],
          positive: net > 0,
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Whether [signals] on one LO show home credit that the supervised work
/// after it contradicts, and how strongly (`PolicyConstants.provenanceGap*`).
///
/// The home side is the home signals that some supervised signal came after;
/// the supervised side is the supervised signals after the first of those.
/// Class work from before the home work is left out: a student who failed
/// in class and then learned it at home is no discrepancy. Fires when each
/// side has [PolicyConstants.provenanceGapMinSignals], the home share of
/// positive signals is above one half and the supervised share below it,
/// and they lie [PolicyConstants.provenanceGapMinShareGap] apart.
ProvenanceGap? detectProvenanceGap({
  required String subgoalId,
  required String loId,
  required List<ProvenanceSignal> signals,
}) {
  final supervisedAll = [
    for (final s in signals)
      if (s.supervised) s,
  ];
  if (supervisedAll.isEmpty) return null;
  final lastSupervised = supervisedAll
      .map((s) => s.at)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final home = [
    for (final s in signals)
      if (!s.supervised && s.at.isBefore(lastSupervised)) s,
  ];
  if (home.length < PolicyConstants.provenanceGapMinSignals) return null;
  final firstHome = home
      .map((s) => s.at)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final later = [
    for (final s in supervisedAll)
      if (s.at.isAfter(firstHome)) s,
  ];
  if (later.length < PolicyConstants.provenanceGapMinSignals) return null;

  final homePositive = home.where((s) => s.positive).length;
  final laterPositive = later.where((s) => s.positive).length;
  final homeShare = homePositive / home.length;
  final laterShare = laterPositive / later.length;
  // Home mostly positive, class mostly negative: the signs differ.
  if (!(homeShare > 0.5 && laterShare < 0.5)) return null;
  // Shares are fractions of small counts: compare with some slack so that
  // e.g. 0.8 - 0.4 is not ruled out by the last bit.
  const slack = 1e-9;
  final shareGap = homeShare - laterShare;
  if (shareGap < PolicyConstants.provenanceGapMinShareGap - slack) return null;

  final strong =
      home.length >= PolicyConstants.provenanceGapStrongMinSignals &&
      later.length >= PolicyConstants.provenanceGapStrongMinSignals &&
      shareGap >= PolicyConstants.provenanceGapStrongMinShareGap - slack;
  return ProvenanceGap(
    subgoalId: subgoalId,
    loId: loId,
    homeSignals: home.length,
    homePositive: homePositive,
    supervisedSignals: later.length,
    supervisedPositive: laterPositive,
    severity: strong
        ? TurnSignalEventSeverity.strong
        : TurnSignalEventSeverity.audit,
  );
}

/// Runs the check after a graded turn and writes the event (#107).
class ProvenanceGapService {
  ProvenanceGapService({required this._turns, required this._supervision});

  final TurnHistoryService _turns;
  final SupervisionSource _supervision;

  /// Checks each target LO of [turn] — the graded turn of [uid] that was
  /// just recorded — and writes a `provenanceGap` event, as an audit record
  /// on the LO's subgoal (`TurnHistoryService.appendAudit`), for each LO
  /// that now shows a gap. Returns the gaps written.
  ///
  /// At most one event per LO per window: a gap already raised in the
  /// window — at the same severity, or strong — is not raised again; an
  /// audit gap that grows strong is. Best-effort and silent: the student
  /// is never told, and a failure only costs the teacher a signal.
  ///
  /// One read of the student's records on the subgoal per graded turn. The
  /// timetable is only read when an LO has enough home signals on the
  /// record — it can turn a recorded `home` into supervised, never the
  /// other way — which since #219 is almost never.
  Future<List<ProvenanceGap>> checkAfter({
    required String uid,
    required PersistedTurnRecord turn,
  }) async {
    try {
      if (turn.questionType.isEmpty) return const [];
      final los = {
        for (final s in turn.appliedSignals)
          if (s.subgoalId == turn.subgoalId &&
              turn.targetLOIds.contains(s.loId) &&
              s.alphaDelta != s.betaDelta)
            s.loId,
      };
      if (los.isEmpty) return const [];

      final from = turn.turnAt.subtract(PolicyConstants.provenanceGapWindow);
      final stored = await _turns.listSubgoalSince(
        uid,
        turn.subgoalId,
        from: from,
      );
      // The write of [turn] runs alongside this read: take the one in hand.
      final records = [
        for (final r in stored)
          if (r.id != turn.id) r,
        turn,
      ]..sort((a, b) => a.turnAt.compareTo(b.turnAt));

      final gaps = <ProvenanceGap>[];
      List<bool>? supervised;
      for (final loId in los) {
        final recorded = directSignalsOn(
          subgoalId: turn.subgoalId,
          loId: loId,
          records: records,
          supervised: [
            for (final r in records)
              r.provenance == EvidenceProvenance.supervised,
          ],
        );
        if (recorded.where((s) => !s.supervised).length <
            PolicyConstants.provenanceGapMinSignals) {
          continue;
        }
        supervised ??= await _supervisedByTimetable(uid, records);
        final gap = detectProvenanceGap(
          subgoalId: turn.subgoalId,
          loId: loId,
          signals: directSignalsOn(
            subgoalId: turn.subgoalId,
            loId: loId,
            records: records,
            supervised: supervised,
          ),
        );
        if (gap == null || _alreadyRaised(records, gap)) continue;
        await _turns.appendAudit(
          subgoalId: gap.subgoalId,
          event: gap.toEvent(),
        );
        gaps.add(gap);
      }
      return gaps;
    } catch (e) {
      debugPrint('ProvenanceGapService: check failed: $e');
      return const [];
    }
  }

  /// Per record: recorded `supervised`, or in a lesson of the student's
  /// class (#219), as the grade proposal's tally reads it.
  Future<List<bool>> _supervisedByTimetable(
    String uid,
    List<PersistedTurnRecord> records,
  ) async {
    final byTimetable = await _supervision.provenancesFor(
      uid: uid,
      ats: [for (final r in records) r.turnAt],
    );
    return [
      for (var i = 0; i < records.length; i++)
        records[i].provenance == EvidenceProvenance.supervised ||
            byTimetable[i] == EvidenceProvenance.supervised,
    ];
  }

  static bool _alreadyRaised(
    List<PersistedTurnRecord> records,
    ProvenanceGap gap,
  ) {
    for (final r in records) {
      for (final e in r.signalEvents) {
        final raised = ProvenanceGap.fromEvent(e);
        if (raised == null ||
            raised.subgoalId != gap.subgoalId ||
            raised.loId != gap.loId) {
          continue;
        }
        if (raised.severity == TurnSignalEventSeverity.strong ||
            raised.severity == gap.severity) {
          return true;
        }
      }
    }
    return false;
  }
}

final provenanceGapServiceProvider = Provider<ProvenanceGapService>(
  (ref) => ProvenanceGapService(
    turns: ref.watch(turnHistoryServiceProvider),
    supervision: ref.watch(supervisionSourceProvider),
  ),
);
