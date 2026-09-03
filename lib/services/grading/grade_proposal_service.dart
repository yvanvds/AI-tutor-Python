// Computes, justifies and signs off grade proposals (#99, PUNTENFORMULE
// part 2). Teacher-side only: every read is addressed by an explicit
// student uid, and the student app never opens `grade_proposals`.
//
// Three steps, each persisted on the same doc:
//   1. [compute]          — the deterministic number from the student model
//                           (`grade_formula.dart`), no LLM involved;
//   2. [writeJustification] — the AI-written narrative around that number;
//   3. [signOff]          — the teacher's (possibly adjusted) grade, after
//                           which the doc is frozen (§5: never recomputed).

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grade_formula.dart';
import 'grade_justification.dart';
import 'grade_proposal.dart';
import 'milestone.dart';
import 'period_start_snapshot.dart';
import 'period_start_snapshot_service.dart';

/// The model call behind [GradeProposalService.writeJustification] failed.
class GradeJustificationException implements Exception {
  const GradeJustificationException(this.cause);
  final Object cause;

  @override
  String toString() => 'GradeJustificationException: $cause';
}

class GradeProposalService {
  GradeProposalService({
    CosmosContainer? container,
    required LoBeliefsService beliefs,
    required GoalsService goals,
    required ProgressService progress,
    required ReportService reports,
    required TurnHistoryService turns,
    required PeriodStartSnapshotService snapshots,
    required OpenaiConnector Function() connector,
    DateTime Function()? now,
  }) : this._(
         container,
         beliefs,
         goals,
         progress,
         reports,
         turns,
         snapshots,
         connector,
         now ?? _utcNow,
       );

  GradeProposalService._(
    this._containerOverride,
    this._beliefs,
    this._goals,
    this._progress,
    this._reports,
    this._turns,
    this._snapshots,
    this._connector,
    this._now,
  );

  static DateTime _utcNow() => DateTime.now().toUtc();

  final CosmosContainer? _containerOverride;
  final LoBeliefsService _beliefs;
  final GoalsService _goals;
  final ProgressService _progress;
  final ReportService _reports;
  final TurnHistoryService _turns;
  final PeriodStartSnapshotService _snapshots;
  final OpenaiConnector Function() _connector;
  final DateTime Function() _now;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.gradeProposals();

  // ---- stored proposals ----------------------------------------------------

  Future<GradeProposal?> getStored(String uid, String milestoneId) =>
      safeCosmos(() async {
        final doc = await _container.read(
          CosmosDocId.gradeProposal(uid, milestoneId),
          partitionKey: uid,
        );
        return doc == null ? null : GradeProposal.fromCosmos(doc);
      });

  /// Every stored proposal of one student, any milestone.
  Stream<List<GradeProposal>> watchForUser(String uid) => safeCosmosStream(
    pollingStream(
      () => safeCosmos(() async {
        final docs = await _container.query(
          'SELECT * FROM c WHERE c.uid = @uid',
          parameters: {'@uid': uid},
          partitionKey: uid,
        );
        return docs.map(GradeProposal.fromCosmos).toList();
      }),
    ),
  );

  Future<void> _save(GradeProposal p) =>
      safeCosmos(() => _container.upsert(p.toMap(), partitionKey: p.uid));

  // ---- 1. the number ---------------------------------------------------------

  /// The proposal for [uid] on [milestone] as of now, persisted as a draft.
  ///
  /// A signed-off proposal is returned as stored, untouched: grades on a
  /// report card are never recomputed (§5). A draft is recomputed; its
  /// justification survives only when the number did not move (a
  /// narrative written for another number would mislead), the teacher's
  /// adjustment and note always survive.
  Future<GradeProposal> compute({
    required String uid,
    required Milestone milestone,
  }) async {
    final stored = await getStored(uid, milestone.id);
    if (stored != null && stored.isSignedOff) return stored;

    final now = _now();
    final goals = await _goals.getAllGoalsOnce();
    final los = milestoneLos(milestone, goals);

    final beliefs = await _beliefs.getAllForUser(uid);
    final beliefByKey = {
      for (final b in beliefs) Milestone.loKey(b.subgoalId, b.loId): b,
    };
    final inputs = {
      for (final lo in los)
        lo.key: LoGradeInput.fromBelief(beliefByKey[lo.key], now: now),
    };
    final end = computeMasteryScore(
      los: los,
      inputs: inputs,
      expectedDifficulty: milestone.expectedDifficulty,
    );

    // M_start (§2.4): the exact per-LO snapshot of this period when the
    // student app has taken one (#110), else the history rule for a period
    // that predates it.
    final double mStart;
    final MStartSource mStartSource;
    var mStartInexact = 0;
    final snapshot = await _snapshots.getStored(uid, milestone.id);
    if (snapshot != null && snapshot.isFor(milestone)) {
      mStart = masteryScoreFromSnapshot(
        los: los,
        snapshot: snapshot,
        expectedDifficulty: milestone.expectedDifficulty,
      );
      mStartSource = MStartSource.snapshot;
      mStartInexact = snapshot.inexactCountFor(los);
    } else {
      final history = await _progress.getHistoryForUser(uid);
      mStart = masteryScoreAtPeriodStart(
        los: los,
        history: history,
        periodStart: milestone.periodStart,
      );
      mStartSource = MStartSource.history;
    }
    final g = growthScore(mStart: mStart, mEnd: end.m);
    final proposal = roundedProposal(proposalScore(mEnd: end.m, g: g));

    var stale = 0;
    var neverProbed = 0;
    for (final lo in los) {
      final b = beliefByKey[lo.key];
      if (b == null) {
        neverProbed += 1;
        stale += 1;
      } else if (now.difference(b.lastUpdatedAt) >
          PolicyConstants.warmUpStaleAfter) {
        stale += 1;
      }
    }

    final turns = await _turns.listTurnsBetween(
      uid,
      from: milestone.periodStart,
      to: now,
    );
    var supervised = 0;
    var home = 0;
    for (final t in turns) {
      if (t.provenance == EvidenceProvenance.supervised) {
        supervised += 1;
      } else {
        home += 1;
      }
    }

    final keepJustification = stored != null && stored.proposal == proposal;
    final result = GradeProposal(
      uid: uid,
      milestoneId: milestone.id,
      formulaVersion: GradingConstants.formulaVersion,
      computedAt: now,
      k: end.k,
      u: end.u,
      d: end.d,
      mEnd: end.m,
      mStart: mStart,
      g: g,
      proposal: proposal,
      coreTotal: end.coreTotal,
      coreCounted: end.coreCounted,
      extensionTotal: end.extensionTotal,
      extensionMastered: end.extensionMastered,
      masteredTotal: end.masteredTotal,
      hardCount: end.hardCount,
      staleLoCount: stale,
      neverProbedCount: neverProbed,
      supervisedTurns: supervised,
      homeTurns: home,
      mStartSource: mStartSource,
      mStartInexactCount: mStartInexact,
      justification: keepJustification ? stored.justification : null,
      justificationAt: keepJustification ? stored.justificationAt : null,
      adjustedGrade: stored?.adjustedGrade,
      adjustmentNote: stored?.adjustmentNote ?? '',
    );
    await _save(result);
    return result;
  }

  // ---- 2. the narrative --------------------------------------------------------

  /// Asks the model for the justification of [proposal] and stores it on
  /// the doc. [studentName] and [calibrationLevel] come from the account
  /// the teacher is looking at; [languageCode] is the UI language.
  Future<GradeProposal> writeJustification({
    required GradeProposal proposal,
    required Milestone milestone,
    required String studentName,
    required String calibrationLevel,
    required String languageCode,
  }) async {
    final now = _now();
    final goals = await _goals.getAllGoalsOnce();
    final goalById = {for (final g in goals) g.id: g};
    final los = milestoneLos(milestone, goals);
    final subgoalIds = {for (final lo in los) lo.subgoalId};

    final allReports = await _reports.getStatusReportsForUser(proposal.uid);
    final reports = <JustificationReport>[
      for (final r in allReports)
        if (r.updatedAt != null &&
            !r.updatedAt!.isBefore(milestone.periodStart) &&
            !r.updatedAt!.isAfter(now))
          (
            title: goalById[r.goalID]?.title ?? r.goalID,
            text: r.statusReport,
            at: r.updatedAt,
          ),
    ]..sort((a, b) => a.at!.compareTo(b.at!));

    final history = await _progress.getHistoryForUser(proposal.uid);
    final startByGoal = progressAt(history, milestone.periodStart);
    final endByGoal = progressAt(history, now);
    final trajectory = <JustificationTrajectory>[
      for (final id in milestone.subgoalIds)
        if (subgoalIds.contains(id))
          (
            title: goalById[id]?.title ?? id,
            start: startByGoal[id] ?? 0.0,
            end: endByGoal[id] ?? 0.0,
          ),
    ];

    final prompt = buildJustificationPrompt(
      proposal: proposal,
      milestone: milestone,
      studentName: studentName,
      calibrationLevel: calibrationLevel,
      reports: reports,
      trajectory: trajectory,
      languageCode: languageCode,
    );
    final result = await _connector().sendRequest(
      instructions: prompt.instructions,
      input: prompt.input,
      inputs: PreviousInputs.newSession,
    );
    switch (result) {
      case ConnectorFailure(:final error):
        throw GradeJustificationException(error);
      case ConnectorOk(:final output):
        final text = extractJustificationText(output);
        if (text.isEmpty) {
          throw const GradeJustificationException('empty reply');
        }
        final updated = proposal.copyWith(
          justification: text,
          justificationAt: now,
        );
        await _save(updated);
        return updated;
    }
  }

  // ---- 3. the signature ---------------------------------------------------------

  /// Records the teacher's decision. [adjustedGrade] is what goes on the
  /// report card; [note] is the context the system could not see.
  Future<GradeProposal> signOff({
    required GradeProposal proposal,
    required int adjustedGrade,
    required String note,
  }) async {
    final signed = proposal.copyWith(
      adjustedGrade: adjustedGrade.clamp(0, 100),
      adjustmentNote: note.trim(),
      signedOffAt: _now(),
    );
    await _save(signed);
    return signed;
  }

  // ---- helpers (pure; unit-tested through the service) ------------------------

  /// The milestone's LOs in curriculum order, from the live goal tree. A
  /// subgoal that no longer exists contributes nothing.
  static List<MilestoneLo> milestoneLos(Milestone milestone, List<Goal> goals) {
    final goalById = {for (final g in goals) g.id: g};
    return [
      for (final sid in milestone.subgoalIds)
        for (final o in goalById[sid]?.objectives ?? const [])
          MilestoneLo(
            subgoalId: sid,
            loId: o.id,
            isCore: milestone.isCore(sid, o.id),
          ),
    ];
  }

  /// Latest stored progress fraction per subgoal at or before [at].
  static Map<String, double> progressAt(
    List<ProgressSample> history,
    DateTime at,
  ) {
    final latestAt = <String, DateTime>{};
    final out = <String, double>{};
    for (final s in history) {
      if (s.at.isAfter(at)) continue;
      final prev = latestAt[s.goalID];
      if (prev == null || !s.at.isBefore(prev)) {
        latestAt[s.goalID] = s.at;
        out[s.goalID] = s.progress;
      }
    }
    return out;
  }

  /// `M_start` (§2.4) from the period-start snapshot (#110): the same §2.3
  /// arithmetic as `M_end`, over the per-LO mastery and ratchet the student
  /// app froze at `periodStart`. An LO the snapshot does not list had no
  /// belief at the period start: never probed, not mastered.
  static double masteryScoreFromSnapshot({
    required List<MilestoneLo> los,
    required PeriodStartSnapshot snapshot,
    required QuestionDifficulty expectedDifficulty,
  }) => computeMasteryScore(
    los: los,
    inputs: snapshot.inputs,
    expectedDifficulty: expectedDifficulty,
  ).m;

  /// `M_start` (§2.4) from the stored history — the v1.0.5 rule, kept for
  /// periods that predate the snapshot: the history holds one mastered
  /// *fraction* per subgoal, not per-LO mastery, so each LO of a subgoal
  /// is credited that subgoal's fraction as of [periodStart] (0 when the
  /// subgoal had no sample yet), on both the core and the extension side,
  /// and nothing is assumed about the difficulty ratchet (`d_start = 0`).
  /// Deterministic and recomputable from the same stored data a student
  /// can ask for.
  static double masteryScoreAtPeriodStart({
    required List<MilestoneLo> los,
    required List<ProgressSample> history,
    required DateTime periodStart,
  }) {
    final fraction = progressAt(history, periodStart);
    var coreTotal = 0;
    var coreSum = 0.0;
    var extTotal = 0;
    var extSum = 0.0;
    for (final lo in los) {
      final p = (fraction[lo.subgoalId] ?? 0.0).clamp(0.0, 1.0);
      if (lo.isCore) {
        coreTotal += 1;
        coreSum += p;
      } else {
        extTotal += 1;
        extSum += p;
      }
    }
    final k = coreTotal == 0 ? 1.0 : coreSum / coreTotal;
    final u = extTotal == 0 ? 0.0 : extSum / extTotal;
    return masteryFromFractions(k: k, u: u, d: 0.0);
  }
}

/// The model behind the justification. Its own connector, not the tutor's:
/// the tutor's carries the student's conversation history and resend
/// state, neither of which belongs in a teacher-side call. The harness
/// overrides this with the scripted model.
final gradeJustificationConnectorProvider = Provider<OpenaiConnector>(
  (ref) => OpenaiConnector(
    getConfig: () => ref.read(globalConfigServiceProvider),
    getModelOverride: () => ref.read(modelPreferenceProvider),
  ),
);

final gradeProposalServiceProvider = Provider<GradeProposalService>(
  (ref) => GradeProposalService(
    beliefs: ref.read(loBeliefsServiceProvider),
    goals: ref.read(goalsServiceProvider),
    progress: ref.read(progressServiceProvider),
    reports: ref.read(reportServiceProvider),
    turns: ref.read(turnHistoryServiceProvider),
    snapshots: ref.read(periodStartSnapshotServiceProvider),
    connector: () => ref.read(gradeJustificationConnectorProvider),
  ),
);
