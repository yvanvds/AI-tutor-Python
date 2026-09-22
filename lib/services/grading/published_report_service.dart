// Publication of approved grade proposals (#150): the step that turns a
// signed-off `GradeProposal` into the frozen, student-facing report of the
// `reports` container.
//
// Sign-off and release are two actions on purpose. The teacher signs a
// class off across a couple of evenings, and student A must not read their
// grade on Tuesday while student B waits until Thursday — so sign-off stays
// per student (`GradeProposalService.signOff`) and [publish] is one action
// per milestone, pressed at the moment the grades go into Smartschool. An
// unreleased milestone has no docs here at all, and a student with no data
// in the period has nothing to sign and so is never published.
//
// Nothing here recomputes, re-reads the student model or asks the model
// anything: the numbers are whatever the signed proposal froze.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grade_proposal.dart';
import 'milestone.dart';
import 'published_report.dart';

class PublishedReportService {
  PublishedReportService({CosmosContainer? container, DateTime Function()? now})
    : _containerOverride = container,
      _now = now ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final CosmosContainer? _containerOverride;
  final DateTime Function() _now;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.reports();

  /// The published report of [uid] for [milestoneId], or `null` when that
  /// student's report has not been released.
  Future<PublishedReport?> getStored(String uid, String milestoneId) =>
      safeCosmos(() async {
        final doc = await _container.read(
          CosmosDocId.publishedReport(uid, milestoneId),
          partitionKey: uid,
        );
        return doc == null ? null : PublishedReport.fromCosmos(doc);
      });

  /// Every published report of one student, newest report date first — the
  /// student's own read (#151).
  ///
  /// Single-partition: this is the query the container was partitioned by
  /// `/uid` for, so a student's tab reads their own partition and nothing
  /// else. Polled like every other student-facing stream, so a report
  /// released while the tab is open appears on the next tick instead of on
  /// the next launch.
  ///
  /// Only published docs exist here at all (an unreleased milestone has none
  /// — see [publish]), so "what this student may read" needs no filter.
  Stream<List<PublishedReport>> watchForUser(String uid) => safeCosmosStream(
    pollingStream(
      () => safeCosmos(() async {
        final docs = await _container.query(
          'SELECT * FROM c WHERE c.uid = @uid',
          parameters: {'@uid': uid},
          partitionKey: uid,
        );
        return docs.map(PublishedReport.fromCosmos).toList()..sort((a, b) {
          // Newest report moment first; the rest of the ordering only has
          // to be stable, so two milestones due the same day don't swap
          // places on every poll.
          final byDue = b.dueAt.compareTo(a.dueAt);
          if (byDue != 0) return byDue;
          final byPublished = b.publishedAt.compareTo(a.publishedAt);
          return byPublished != 0
              ? byPublished
              : a.milestoneId.compareTo(b.milestoneId);
        });
      }),
    ),
  );

  /// Every published report of one milestone, across students.
  ///
  /// Cross-partition by necessity — the container is partitioned by `/uid`
  /// for the student read, and the teacher's Reports page asks the other
  /// question ("this milestone, who is out?"). A handful of docs per
  /// milestone, read once when the teacher picks one.
  Future<List<PublishedReport>> getForMilestone(String milestoneId) =>
      safeCosmos(() async {
        final docs = await _container.query(
          'SELECT * FROM c WHERE c.milestoneId = @milestoneId',
          parameters: {'@milestoneId': milestoneId},
          crossPartition: true,
        );
        return docs.map(PublishedReport.fromCosmos).toList();
      });

  /// Releases [proposals] — the milestone's batch action.
  ///
  /// A proposal that is not signed off is skipped rather than refused: the
  /// teacher presses this with a class in whatever state it is in, and
  /// "publish everything approved" is exactly what they mean. Returns the
  /// docs as they now stand on the server, for the rows that were
  /// published.
  ///
  /// Idempotent for unchanged reports: pressing release again for a class
  /// that is already out keeps each report's [PublishedReport.publishedAt]
  /// and does not stamp a new [PublishedReport.updatedAt] on prose nobody
  /// touched.
  Future<List<PublishedReport>> publish({
    required Milestone milestone,
    required Iterable<GradeProposal> proposals,
  }) async {
    final at = _now();
    final out = <PublishedReport>[];
    for (final proposal in proposals) {
      if (!proposal.isSignedOff) continue;
      final written = await _write(
        proposal: proposal,
        milestone: milestone,
        at: at,
        onlyIfPublished: false,
      );
      if (written != null) out.add(written);
    }
    return out;
  }

  /// Rewrites the already-published report of one student.
  ///
  /// The prose is the teacher's to rewrite after sign-off (#149): §5 freezes
  /// the grade, not the sentence explaining it. When the report is already
  /// out, leaving the old wording on the student's page would make the app
  /// contradict the conversation that produced the new one — so the copy is
  /// overwritten with a fresh [PublishedReport.updatedAt] and no revision
  /// history. `null` when this student's report was never released, which is
  /// the normal case: release has not happened yet, and nothing should leak
  /// out ahead of it.
  Future<PublishedReport?> republish({
    required Milestone milestone,
    required GradeProposal proposal,
  }) => _write(
    proposal: proposal,
    milestone: milestone,
    at: _now(),
    onlyIfPublished: true,
  );

  Future<PublishedReport?> _write({
    required GradeProposal proposal,
    required Milestone milestone,
    required DateTime at,
    required bool onlyIfPublished,
  }) async {
    final existing = await getStored(proposal.uid, milestone.id);
    if (existing == null && onlyIfPublished) return null;
    final fresh = PublishedReport.of(
      proposal: proposal,
      milestone: milestone,
      publishedAt: existing?.publishedAt ?? at,
      updatedAt: at,
    );
    if (existing != null && existing.sameContentAs(fresh)) return existing;
    await safeCosmos(
      () => _container.upsert(fresh.toMap(), partitionKey: fresh.uid),
    );
    return fresh;
  }
}

final publishedReportServiceProvider = Provider<PublishedReportService>(
  (ref) => PublishedReportService(),
);
