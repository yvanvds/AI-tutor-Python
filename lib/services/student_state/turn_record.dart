// Persisted turn record per CONDUCTOR_POLICY 8.1.
//
// One append-only doc per graded turn. Same schema is mirrored in-memory by
// `DebugSessionRecorder` (CONDUCTOR_POLICY 8.3) so debug-dialog inspection and
// the persisted audit trail stay aligned.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';

class CandidateLoStat {
  final String loId;
  final double mean;
  final double evidence;
  const CandidateLoStat({
    required this.loId,
    required this.mean,
    required this.evidence,
  });

  Map<String, dynamic> toJson() => {
    'loId': loId,
    'mean': mean,
    'evidence': evidence,
  };
}

class TurnLoSignal {
  final String subgoalId;
  final String loId;
  final String signal; // positive | negative | neutral
  final String strength; // strong | moderate | weak
  const TurnLoSignal({
    required this.subgoalId,
    required this.loId,
    required this.signal,
    required this.strength,
  });

  Map<String, dynamic> toJson() => {
    'subgoalId': subgoalId,
    'loId': loId,
    'signal': signal,
    'strength': strength,
  };
}

class TurnAppliedSignal {
  final String loId;
  final double alphaDelta;
  final double betaDelta;
  const TurnAppliedSignal({
    required this.loId,
    required this.alphaDelta,
    required this.betaDelta,
  });

  Map<String, dynamic> toJson() => {
    'loId': loId,
    'alphaDelta': alphaDelta,
    'betaDelta': betaDelta,
  };
}

class TurnLoStatus {
  final String loId;
  final double mean;
  final double evidence;
  final bool mastered;
  final bool stuck;
  const TurnLoStatus({
    required this.loId,
    required this.mean,
    required this.evidence,
    required this.mastered,
    required this.stuck,
  });

  Map<String, dynamic> toJson() => {
    'loId': loId,
    'mean': mean,
    'evidence': evidence,
    'mastered': mastered,
    'stuck': stuck,
  };
}

/// One observability event captured on a `turn_history` doc per
/// CONDUCTOR_POLICY §8.2. Strong-severity events drive the
/// "needs attention" badge on the teacher dashboard until acknowledged;
/// audit-severity events are visible in the detail drawer without a badge.
///
/// Doc-side schema amendment: §8.1 lists the `TurnRecord` fields, but does
/// not enumerate the strong/audit split. Adding it here so the conductor can
/// emit and the dashboard can query without inventing parallel containers.
enum TurnSignalEventKind {
  // Strong (badge-driving):
  stuckLoAdvance,
  singleLoDeadlock,
  repeatedDemotions,
  sustainedLlmFailure,
  // Audit-only:
  cascadeHalt,
  emptyObjectivesBlock,
  subgoalDeletedRedirect,
}

enum TurnSignalEventSeverity { strong, audit }

class TurnSignalEvent {
  final TurnSignalEventKind kind;
  final TurnSignalEventSeverity severity;
  final Map<String, Object?> details;

  const TurnSignalEvent({
    required this.kind,
    required this.severity,
    this.details = const {},
  });

  /// Default severity for each kind. Kept here so emission sites only need to
  /// pass the kind; severity follows from the policy classification.
  static TurnSignalEventSeverity severityFor(TurnSignalEventKind k) {
    switch (k) {
      case TurnSignalEventKind.stuckLoAdvance:
      case TurnSignalEventKind.singleLoDeadlock:
      case TurnSignalEventKind.repeatedDemotions:
      case TurnSignalEventKind.sustainedLlmFailure:
        return TurnSignalEventSeverity.strong;
      case TurnSignalEventKind.cascadeHalt:
      case TurnSignalEventKind.emptyObjectivesBlock:
      case TurnSignalEventKind.subgoalDeletedRedirect:
        return TurnSignalEventSeverity.audit;
    }
  }

  factory TurnSignalEvent.of(
    TurnSignalEventKind k, {
    Map<String, Object?> details = const {},
  }) {
    return TurnSignalEvent(kind: k, severity: severityFor(k), details: details);
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'severity': severity.name,
    if (details.isNotEmpty) 'details': details,
  };

  static TurnSignalEvent? tryFromJson(Map<String, dynamic> map) {
    final kindRaw = map['kind'];
    if (kindRaw is! String) return null;
    TurnSignalEventKind? kind;
    for (final k in TurnSignalEventKind.values) {
      if (k.name == kindRaw) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    final sevRaw = map['severity'];
    var sev = severityFor(kind);
    for (final s in TurnSignalEventSeverity.values) {
      if (s.name == sevRaw) {
        sev = s;
        break;
      }
    }
    final detailsRaw = map['details'];
    final details = detailsRaw is Map
        ? Map<String, Object?>.from(detailsRaw.cast<String, Object?>())
        : const <String, Object?>{};
    return TurnSignalEvent(kind: kind, severity: sev, details: details);
  }
}

class TurnSelectionReason {
  final List<CandidateLoStat> candidateLOs;
  final String chosenReason;
  final bool notchDropFired;

  const TurnSelectionReason({
    required this.candidateLOs,
    required this.chosenReason,
    required this.notchDropFired,
  });

  Map<String, dynamic> toJson() => {
    'candidateLOs': candidateLOs.map((c) => c.toJson()).toList(),
    'chosenReason': chosenReason,
    'notchDropFired': notchDropFired,
  };
}

/// Persisted shape for one graded turn (CONDUCTOR_POLICY 8.1).
class PersistedTurnRecord {
  final String id;
  final DateTime turnAt;
  final String subgoalId;

  // What was asked
  final List<String> targetLOIds;
  final String questionType;
  final QuestionDifficulty? difficulty;
  final bool isFollowUp;
  final int chainDepth;

  // Why these were picked
  final TurnSelectionReason? selectionReason;

  // What happened
  final AnswerQuality overallQuality;
  final List<TurnLoSignal> loSignals;
  final bool hadFallback;
  final List<TurnAppliedSignal> appliedSignals;

  /// Where the answer was produced (#100): the supervision registry's
  /// verdict for this student at `turnAt`. `appliedSignals` already carry
  /// the resulting weight; this records *why*, so a teacher (or the
  /// student, per PUNTENFORMULE §2.7) can tell supervised from home
  /// evidence. Missing on docs written before the field existed → `home`.
  final EvidenceProvenance provenance;

  // Calibration impact
  final QuestionDifficulty calibrationBefore;
  final QuestionDifficulty calibrationAfter;

  // Subgoal status after this turn
  final double subgoalProgressAfter;
  final List<TurnLoStatus> loStatusAfter;
  final bool subgoalAdvanced;

  final DateTime? acknowledgedAt;

  /// Observability events surfacing on the teacher dashboard
  /// (CONDUCTOR_POLICY §8.2). Empty for ordinary turns; one or more entries
  /// when a strong-signal or audit-only condition fired.
  final List<TurnSignalEvent> signalEvents;

  const PersistedTurnRecord({
    required this.id,
    required this.turnAt,
    required this.subgoalId,
    required this.targetLOIds,
    required this.questionType,
    required this.difficulty,
    required this.isFollowUp,
    required this.chainDepth,
    required this.selectionReason,
    required this.overallQuality,
    required this.loSignals,
    required this.hadFallback,
    required this.appliedSignals,
    required this.calibrationBefore,
    required this.calibrationAfter,
    required this.subgoalProgressAfter,
    required this.loStatusAfter,
    required this.subgoalAdvanced,
    this.acknowledgedAt,
    this.signalEvents = const [],
    this.provenance = EvidenceProvenance.home,
  });

  bool get hasStrongEvent =>
      signalEvents.any((e) => e.severity == TurnSignalEventSeverity.strong);

  Map<String, dynamic> toMap({required String uid}) => {
    'id': id,
    'type': 'turn_history',
    'uid': uid,
    'turnAt': turnAt.toUtc().toIso8601String(),
    'subgoalId': subgoalId,
    'targetLOIds': targetLOIds,
    'questionType': questionType,
    if (difficulty != null) 'difficulty': difficulty!.name,
    'isFollowUp': isFollowUp,
    'chainDepth': chainDepth,
    if (selectionReason != null) 'selectionReason': selectionReason!.toJson(),
    'overallQuality': overallQuality.name,
    'loSignals': loSignals.map((s) => s.toJson()).toList(),
    'hadFallback': hadFallback,
    'appliedSignals': appliedSignals.map((s) => s.toJson()).toList(),
    'provenance': provenance.name,
    'calibrationBefore': calibrationBefore.name,
    'calibrationAfter': calibrationAfter.name,
    'subgoalProgressAfter': subgoalProgressAfter,
    'loStatusAfter': loStatusAfter.map((s) => s.toJson()).toList(),
    'subgoalAdvanced': subgoalAdvanced,
    if (acknowledgedAt != null)
      'acknowledgedAt': acknowledgedAt!.toUtc().toIso8601String(),
    if (signalEvents.isNotEmpty)
      'signalEvents': signalEvents.map((e) => e.toJson()).toList(),
  };

  /// Best-effort parse of a `turn_history` doc as written by `toMap`.
  /// Designed for the teacher-dashboard query path; defaults are conservative
  /// so a partial / older doc doesn't blow up the list.
  factory PersistedTurnRecord.fromCosmos(Map<String, dynamic> doc) {
    DateTime parseDate(Object? raw) {
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.utc(1970);
      return DateTime.utc(1970);
    }

    AnswerQuality parseQuality(Object? raw) {
      if (raw is String) {
        for (final q in AnswerQuality.values) {
          if (q.name == raw) return q;
        }
      }
      return AnswerQuality.wrong;
    }

    QuestionDifficulty? parseDifficulty(Object? raw) {
      if (raw is! String) return null;
      for (final d in QuestionDifficulty.values) {
        if (d.name == raw) return d;
      }
      return null;
    }

    QuestionDifficulty parseDifficultyOr(Object? raw) =>
        parseDifficulty(raw) ?? QuestionDifficulty.medium;

    final events = <TurnSignalEvent>[];
    final eventsRaw = doc['signalEvents'];
    if (eventsRaw is List) {
      for (final entry in eventsRaw) {
        if (entry is Map) {
          final ev = TurnSignalEvent.tryFromJson(entry.cast<String, dynamic>());
          if (ev != null) events.add(ev);
        }
      }
    }

    return PersistedTurnRecord(
      id: (doc['id'] as String?) ?? '',
      turnAt: parseDate(doc['turnAt']),
      subgoalId: (doc['subgoalId'] as String?) ?? '',
      targetLOIds:
          (doc['targetLOIds'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      questionType: (doc['questionType'] as String?) ?? '',
      difficulty: parseDifficulty(doc['difficulty']),
      isFollowUp: (doc['isFollowUp'] as bool?) ?? false,
      chainDepth: (doc['chainDepth'] as num?)?.toInt() ?? 0,
      selectionReason: null, // not consumed by dashboard reads; keep tiny
      overallQuality: parseQuality(doc['overallQuality']),
      loSignals: const [],
      hadFallback: (doc['hadFallback'] as bool?) ?? false,
      appliedSignals: const [],
      provenance: EvidenceProvenance.parse(doc['provenance']),
      calibrationBefore: parseDifficultyOr(doc['calibrationBefore']),
      calibrationAfter: parseDifficultyOr(doc['calibrationAfter']),
      subgoalProgressAfter:
          (doc['subgoalProgressAfter'] as num?)?.toDouble() ?? 0.0,
      loStatusAfter: const [],
      subgoalAdvanced: (doc['subgoalAdvanced'] as bool?) ?? false,
      acknowledgedAt: doc['acknowledgedAt'] is String
          ? DateTime.tryParse(doc['acknowledgedAt'] as String)
          : null,
      signalEvents: events,
    );
  }
}
