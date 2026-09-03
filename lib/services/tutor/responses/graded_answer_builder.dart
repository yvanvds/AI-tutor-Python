// Bridges the LLM-grader response models to the conductor's `GradedAnswer`.
// Implements the validation rules from `docs/LLM_CONTRACT.md`
// "Validation on the conductor side": schema, LO id resolution, scope check,
// and the single-failure fallback.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';

class GradedAnswerBuilder {
  /// Build a `GradedAnswer` for the conductor to integrate.
  ///
  /// [scopeSubgoals] is the current root goal's subgoals (the LO scope per
  /// LLM_CONTRACT). Each (subgoalId, loId) signal must resolve into a live
  /// LO somewhere in this scope; unresolved or out-of-scope entries are
  /// dropped. When every signal drops, a fallback weak signal on the
  /// intended LO is synthesised.
  ///
  /// [rawTransferLOs] (#101) get the same scope check and are de-duplicated;
  /// they never count toward "every signal dropped" — transfer credit is
  /// not a substitute for a graded signal on the target.
  static GradedAnswer build({
    required AnswerQuality overallQuality,
    required List<LoSignal> rawSignals,
    required List<Goal> scopeSubgoals,
    required LearningObjective? intendedTargetLO,
    required String? intendedTargetSubgoalId,
    List<TransferLoRef> rawTransferLOs = const [],
    bool isFollowUp = false,
    int chainDepth = 0,
    EvidenceProvenance provenance = EvidenceProvenance.home,
  }) {
    final scopeIndex = <String, Set<String>>{};
    for (final sub in scopeSubgoals) {
      scopeIndex[sub.id] = sub.objectives.map((o) => o.id).toSet();
    }

    final accepted = <GradedSignal>[];
    for (final sig in rawSignals) {
      final loIds = scopeIndex[sig.subgoalId];
      if (loIds == null) continue;
      if (!loIds.contains(sig.loId)) continue;
      accepted.add(
        GradedSignal(
          subgoalId: sig.subgoalId,
          loId: sig.loId,
          kind: sig.kind,
          strength: sig.strength,
        ),
      );
    }

    final transfers = <GradedTransfer>[];
    final seenTransfers = <String>{};
    for (final ref in rawTransferLOs) {
      final loIds = scopeIndex[ref.subgoalId];
      if (loIds == null) continue;
      if (!loIds.contains(ref.loId)) continue;
      if (!seenTransfers.add('${ref.subgoalId}/${ref.loId}')) continue;
      transfers.add(GradedTransfer(subgoalId: ref.subgoalId, loId: ref.loId));
    }

    if (accepted.isNotEmpty) {
      return GradedAnswer(
        overallQuality: overallQuality,
        signals: accepted,
        hadFallback: false,
        isFollowUp: isFollowUp,
        chainDepth: chainDepth,
        provenance: provenance,
        transferLOs: transfers,
      );
    }

    // Fallback: single weak signal on the intended target.
    if (intendedTargetLO == null || intendedTargetSubgoalId == null) {
      return GradedAnswer(
        overallQuality: overallQuality,
        signals: const [],
        hadFallback: true,
        isFollowUp: isFollowUp,
        chainDepth: chainDepth,
        provenance: provenance,
        transferLOs: transfers,
      );
    }
    final fallbackKind = switch (overallQuality) {
      AnswerQuality.correct => LoSignalKind.positive,
      AnswerQuality.partial => LoSignalKind.neutral,
      AnswerQuality.wrong => LoSignalKind.negative,
    };
    return GradedAnswer(
      overallQuality: overallQuality,
      signals: [
        GradedSignal(
          subgoalId: intendedTargetSubgoalId,
          loId: intendedTargetLO.id,
          kind: fallbackKind,
          strength: LoSignalStrength.weak,
        ),
      ],
      hadFallback: true,
      isFollowUp: isFollowUp,
      chainDepth: chainDepth,
      provenance: provenance,
      transferLOs: transfers,
    );
  }
}
