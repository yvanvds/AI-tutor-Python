// The class-wide report run (#148).
//
// #99 built the whole chain — compute, justify, adjust, sign off — but only
// one student at a time. This turns it into a batch over every student in a
// class, in the two steps it really has, which cost wildly different things:
//
//   1. `GradeProposalService.compute` is deterministic, free and fast. It
//      runs for every student in one sequential pass.
//   2. `GradeProposalService.writeJustification` is one model call per
//      student. It runs a few at a time, and a student whose call fails
//      keeps their computed number, carries the error, and can be retried
//      on their own.
//
// The run is resumable for free: the Cosmos doc *is* the state. `compute`
// keeps an existing justification when the number did not move, and this
// service only asks the model for students whose doc still has none, so a
// re-run after a crash picks up where it broke instead of re-billing the
// whole class.
//
// That thrift is right for the class run and wrong for the "Recompute"
// button in the detail pane (#166): an explicit action on one student, where
// "skip it, it already exists" reads as a button that does nothing. So
// `runOne(force: true)` is that button — it rewrites an AI justification
// even when the number stayed put, still leaves a teacher-written text alone
// (#149) and a signed-off doc frozen (PUNTENFORMULE §5), and says when the
// number did not move so the page can say so too.
//
// Teacher-side only, like everything else in this folder: every read is
// addressed by an explicit student uid.

import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grade_proposal.dart';
import 'grade_proposal_service.dart';
import 'milestone.dart';

/// Where one student stands on one milestone, as the Reports list shows it.
///
/// Derived from the stored doc alone — there is no separate status field to
/// keep in sync, and a run that died halfway leaves every student on the
/// status their doc honestly has.
enum ReportStatus {
  /// No stored proposal: either nothing has been generated yet, or the
  /// student has no evidence at all for this milestone's learning
  /// objectives and the batch deliberately skipped them (a computed 0 for
  /// a student the system never saw would be a lie, not a grade).
  noData,

  /// The deterministic number is on the doc; no justification yet.
  computed,

  /// The model wrote the justification; the teacher has not signed.
  justified,

  /// Signed off. PUNTENFORMULE §5: never recomputed.
  signedOff,
}

/// [ReportStatus] of [proposal]; `null` means no stored doc.
ReportStatus reportStatusOf(GradeProposal? proposal) {
  if (proposal == null) return ReportStatus.noData;
  if (proposal.isSignedOff) return ReportStatus.signedOff;
  if (proposal.justification != null) return ReportStatus.justified;
  return ReportStatus.computed;
}

/// What the batch has to say about one student, as it happens.
class ReportBatchResult {
  const ReportBatchResult({
    this.proposal,
    this.error,
    this.noData = false,
    this.unchanged = false,
  });

  /// The doc as it now stands, when there is one.
  final GradeProposal? proposal;

  /// The failure of this student's step, if any. A justification failure
  /// leaves [proposal] set — the number survives, only the prose is
  /// missing — so the row can be retried on its own.
  final Object? error;

  /// The student had no belief data for this milestone and was skipped.
  final bool noData;

  /// The recomputed number is the one the doc already had (#166). Set by
  /// [ReportBatchService.runOne] so the page can say so: a recompute that
  /// lands on the same grade otherwise looks like a button that did nothing.
  final bool unchanged;
}

/// Called once per student per step, on the calling (UI) isolate.
typedef ReportBatchUpdate = void Function(String uid, ReportBatchResult result);

class ReportBatchService {
  ReportBatchService({
    required GradeProposalService proposals,
    required LoBeliefsService beliefs,
    required GoalsService goals,
  }) : this._(proposals, beliefs, goals);

  ReportBatchService._(this._proposals, this._beliefs, this._goals);

  final GradeProposalService _proposals;
  final LoBeliefsService _beliefs;
  final GoalsService _goals;

  /// Model calls in flight at once. Small on purpose: a class is 25
  /// students, the teacher is watching the list fill, and the provider's
  /// rate limit is the one resource a batch can actually exhaust.
  static const int defaultConcurrency = 3;

  /// Runs both steps over [students] for [milestone].
  ///
  /// [onResult] fires for every student as their step finishes, so the list
  /// fills in while the run is still going. The future completes when the
  /// last model call has returned; a single student's failure never stops
  /// the run.
  Future<void> run({
    required Milestone milestone,
    required List<Account> students,
    required String languageCode,
    required ReportBatchUpdate onResult,
    int concurrency = defaultConcurrency,
  }) async {
    final keys = await milestoneLoKeys(milestone);
    final pending = <({Account student, GradeProposal proposal})>[];

    // Step 1 — the free one, in one sequential pass.
    for (final student in students) {
      try {
        final computed = await computeFor(
          uid: student.uid,
          milestone: milestone,
          loKeys: keys,
        );
        if (computed == null) {
          onResult(student.uid, const ReportBatchResult(noData: true));
          continue;
        }
        onResult(student.uid, ReportBatchResult(proposal: computed));
        if (computed.justification == null && !computed.isSignedOff) {
          pending.add((student: student, proposal: computed));
        }
      } catch (error) {
        onResult(student.uid, ReportBatchResult(error: error));
      }
    }

    // Step 2 — the expensive one, a few at a time.
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= pending.length) return;
        final (:student, :proposal) = pending[index];
        onResult(
          student.uid,
          await justifyFor(
            proposal: proposal,
            milestone: milestone,
            student: student,
            languageCode: languageCode,
          ),
        );
      }
    }

    final workers = concurrency < 1 ? 1 : concurrency;
    await Future.wait([
      for (var i = 0; i < workers && i < pending.length; i++) worker(),
    ]);
  }

  /// Steps 1 and 2 for a single student — the per-row retry behind a failed
  /// row, and the "recompute this one" action in the detail pane.
  ///
  /// Without [force] this is the batch's rule for one student: an existing
  /// justification is kept and not paid for again, so a retry after a failed
  /// model call finishes the job at the cost of that one call.
  ///
  /// With [force] — the button (#166) — the request is "do it again", not
  /// "fill in what is missing": an AI-written justification is rewritten
  /// even when the number came out the same. Two things still hold. A text
  /// the teacher wrote is theirs and stays (#149), and a signed-off doc is
  /// frozen (PUNTENFORMULE §5) — `compute` hands it back untouched. Either
  /// way [ReportBatchResult.unchanged] reports whether the number moved,
  /// read against the doc as it stood before this call.
  Future<ReportBatchResult> runOne({
    required Milestone milestone,
    required Account student,
    required String languageCode,
    bool force = false,
  }) async {
    final GradeProposal? before;
    final GradeProposal? computed;
    try {
      before = await _proposals.getStored(student.uid, milestone.id);
      computed = await computeFor(uid: student.uid, milestone: milestone);
    } catch (error) {
      return ReportBatchResult(error: error);
    }
    if (computed == null) return const ReportBatchResult(noData: true);
    if (computed.isSignedOff) return ReportBatchResult(proposal: computed);

    final unchanged = before != null && before.proposal == computed.proposal;
    final teacherWrote =
        computed.justificationSource == JustificationSource.edited;
    if (computed.justification != null && (!force || teacherWrote)) {
      return ReportBatchResult(proposal: computed, unchanged: unchanged);
    }
    final justified = await justifyFor(
      proposal: computed,
      milestone: milestone,
      student: student,
      languageCode: languageCode,
    );
    return ReportBatchResult(
      proposal: justified.proposal,
      error: justified.error,
      unchanged: unchanged,
    );
  }

  /// The deterministic step for one student, or `null` when the student has
  /// no belief data for this milestone at all.
  ///
  /// The guard only applies to a student with no stored doc: once a
  /// proposal exists it is recomputed like any other, and a signed-off one
  /// comes back untouched from `compute` itself.
  Future<GradeProposal?> computeFor({
    required String uid,
    required Milestone milestone,
    Set<String>? loKeys,
  }) async {
    final stored = await _proposals.getStored(uid, milestone.id);
    if (stored == null) {
      final keys = loKeys ?? await milestoneLoKeys(milestone);
      if (!await hasEvidence(uid: uid, loKeys: keys)) return null;
    }
    return _proposals.compute(uid: uid, milestone: milestone);
  }

  /// The model step for one student. Never throws: a failure comes back as
  /// [ReportBatchResult.error] next to the number that survived it.
  Future<ReportBatchResult> justifyFor({
    required GradeProposal proposal,
    required Milestone milestone,
    required Account student,
    required String languageCode,
  }) async {
    try {
      final written = await _proposals.writeJustification(
        proposal: proposal,
        milestone: milestone,
        studentName: student.firstName.isEmpty
            ? student.email
            : student.firstName,
        calibrationLevel: student.calibration.difficulty.name,
        languageCode: languageCode,
      );
      return ReportBatchResult(proposal: written);
    } catch (error) {
      return ReportBatchResult(proposal: proposal, error: error);
    }
  }

  /// `loKey`s of every learning objective [milestone] covers, from the live
  /// goal tree. Read once per run rather than once per student.
  Future<Set<String>> milestoneLoKeys(Milestone milestone) async {
    final goals = await _goals.getAllGoalsOnce();
    return {
      for (final lo in GradeProposalService.milestoneLos(milestone, goals))
        lo.key,
    };
  }

  /// Whether the student has ever been probed on any of [loKeys].
  ///
  /// This is the "geen data" guard. It is deliberately about the *existence*
  /// of belief docs, not about their age: a student who mastered the
  /// milestone's objectives before the period still has a real grade (its
  /// mastery score, P = M), while a student the tutor never saw on any of them would
  /// otherwise be handed a computed 0.
  Future<bool> hasEvidence({
    required String uid,
    required Set<String> loKeys,
  }) async {
    if (loKeys.isEmpty) return false;
    final beliefs = await _beliefs.getAllForUser(uid);
    return beliefs.any(
      (b) => loKeys.contains(Milestone.loKey(b.subgoalId, b.loId)),
    );
  }
}

final reportBatchServiceProvider = Provider<ReportBatchService>(
  (ref) => ReportBatchService(
    proposals: ref.read(gradeProposalServiceProvider),
    beliefs: ref.read(loBeliefsServiceProvider),
    goals: ref.read(goalsServiceProvider),
  ),
);
