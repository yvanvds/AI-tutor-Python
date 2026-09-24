// `PublishedReport` / `PublishedReportService` (#150): turning an approved
// grade proposal into the frozen, student-facing report of the `reports`
// container.
//
// What it has to get right:
//   - the published doc carries what the student sees and *not* the two
//     things the issue rules out — the supervised/home turn tally and the
//     staleness diagnostics;
//   - release is per milestone and publishes only what is signed off: an
//     unsigned row stays on the teacher's side, and a student with no data
//     (hence no proposal at all) is never published;
//   - pressing release again keeps `publishedAt` and leaves `updatedAt`
//     alone for reports nobody touched;
//   - a post-sign-off rewrite of the prose (#149) republishes: overwrite,
//     fresh `updatedAt`, no revision history — and it is a no-op for a
//     student whose report was never released.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/published_report.dart';
import 'package:ai_tutor_python/services/grading/published_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

final DateTime _computedAt = DateTime.utc(2026, 10, 15, 12);
final DateTime _released = DateTime.utc(2026, 10, 20, 17, 30);

Milestone _milestone({
  String id = 'm1',
  String title = 'Rapport 1',
  DateTime? dueAt,
}) => Milestone(
  id: id,
  title: title,
  periodStart: DateTime.utc(2026, 9, 1),
  dueAt: dueAt ?? DateTime.utc(2026, 10, 15),
  expectedDifficulty: QuestionDifficulty.hard,
  subgoalIds: const ['s1'],
  coreLoKeys: {Milestone.loKey('s1', 'a')},
);

GradeProposal _proposal({
  String uid = 'u1',
  String? justification = 'Sam beheerst de kern.',
  int? adjustedGrade = 84,
  String note = 'Ziek in week 3.',
  DateTime? signedOffAt,
}) => GradeProposal(
  uid: uid,
  milestoneId: 'm1',
  formulaVersion: '1.0.7',
  computedAt: _computedAt,
  k: 1,
  u: 0.5,
  d: 0.5,
  mEnd: 90,
  proposal: 86,
  coreTotal: 2,
  coreCounted: 2,
  extensionTotal: 4,
  extensionMastered: 2,
  masteredTotal: 4,
  hardCount: 1,
  // The four fields a published report must not carry.
  staleLoCount: 3,
  neverProbedCount: 2,
  supervisedTurns: 41,
  homeTurns: 7,
  justification: justification,
  justificationAt: _computedAt,
  adjustedGrade: adjustedGrade,
  adjustmentNote: note,
  signedOffAt: signedOffAt,
);

GradeProposal _signed({
  String uid = 'u1',
  String? justification = 'Sam beheerst de kern.',
}) => _proposal(
  uid: uid,
  justification: justification,
  signedOffAt: DateTime.utc(2026, 10, 19),
);

class _Fixture {
  final InMemoryCosmos store = InMemoryCosmos();
  DateTime now = _released;

  late final PublishedReportService service = PublishedReportService(
    container: store.container,
    now: () => now,
  );
}

void main() {
  group('PublishedReport.of', () {
    test('copies what the student sees', () {
      final report = PublishedReport.of(
        proposal: _signed(),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released,
      );

      expect(report.uid, 'u1');
      expect(report.milestoneId, 'm1');
      expect(report.milestoneTitle, 'Rapport 1');
      expect(report.dueAt, DateTime.utc(2026, 10, 15));
      // The teacher's number, not the raw proposal.
      expect(report.grade, 84);
      expect(report.justification, 'Sam beheerst de kern.');
      expect(report.note, 'Ziek in week 3.');
      expect(report.computedAt, _computedAt);
      expect(report.publishedAt, _released);
      expect(report.updatedAt, _released);
      expect(report.isRepublished, isFalse);
      expect(report.formulaVersion, '1.0.7');
      // The breakdown a student may recompute.
      expect(report.mEnd, 90);
      expect(report.k, 1);
      expect(report.u, 0.5);
      expect(report.d, 0.5);
      expect(report.coreCounted, 2);
      expect(report.coreTotal, 2);
      expect(report.extensionMastered, 2);
      expect(report.extensionTotal, 4);
      expect(report.expectedDifficulty, QuestionDifficulty.hard);
    });

    test('carries no turn tally and no staleness diagnostics', () {
      final doc = PublishedReport.of(
        proposal: _signed(),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released,
      ).toMap();

      // A surveillance count on a student's own page (§2.7 discloses the
      // principle), and teacher diagnostics that read as an accusation.
      expect(doc.keys, isNot(contains('supervisedTurns')));
      expect(doc.keys, isNot(contains('homeTurns')));
      expect(doc.keys, isNot(contains('staleLoCount')));
      expect(doc.keys, isNot(contains('neverProbedCount')));
      // Nor the raw proposal next to the grade that was signed.
      expect(doc.keys, isNot(contains('proposal')));
      expect(doc['id'], 'u1_m1');
      expect(doc['type'], 'report');
    });

    test('a report signed off without a justification publishes an empty '
        'text rather than nothing', () {
      final report = PublishedReport.of(
        proposal: _signed(justification: null),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released,
      );
      expect(report.justification, '');
    });

    test('survives a Cosmos round trip', () {
      final report = PublishedReport.of(
        proposal: _signed(),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released.add(const Duration(days: 1)),
      );
      final back = PublishedReport.fromCosmos(report.toMap());

      expect(back.sameContentAs(report), isTrue);
      expect(back.updatedAt, report.updatedAt);
      expect(back.isRepublished, isTrue);
    });

    test('P = M (#191): no period-start score or growth is written, and a '
        'report published before v1.0.16 that carries them still reads', () {
      final report = PublishedReport.of(
        proposal: _signed(),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released,
      );
      final doc = report.toMap();
      expect(doc.containsKey('mStart'), isFalse);
      expect(doc.containsKey('g'), isFalse);

      final old = {...doc, 'mStart': 50.0, 'g': 0.8};
      final back = PublishedReport.fromCosmos(old);
      expect(back.sameContentAs(report), isTrue);
    });

    test('a doc with no updatedAt reads as never revised', () {
      final doc = PublishedReport.of(
        proposal: _signed(),
        milestone: _milestone(),
        publishedAt: _released,
        updatedAt: _released,
      ).toMap()..remove('updatedAt');

      final back = PublishedReport.fromCosmos(doc);
      expect(back.updatedAt, _released);
      expect(back.isRepublished, isFalse);
    });
  });

  group('publish', () {
    test('writes one doc per signed-off proposal and skips the rest', () async {
      final f = _Fixture();

      final published = await f.service.publish(
        milestone: _milestone(),
        proposals: [
          _signed(),
          // Computed and justified, but nobody signed it: it stays on the
          // teacher's side.
          _proposal(uid: 'u2'),
        ],
      );

      expect(published.map((r) => r.uid), ['u1']);
      expect(f.store.docs.keys, ['u1_m1']);
      final doc = f.store.docs['u1_m1']!;
      expect(doc['grade'], 84);
      expect(doc['justification'], 'Sam beheerst de kern.');
      expect(doc['publishedAt'], _released.toIso8601String());
      expect(doc['updatedAt'], _released.toIso8601String());
    });

    test(
      'an unreleased milestone has nothing in the container at all',
      () async {
        final f = _Fixture();
        expect(await f.service.getForMilestone('m1'), isEmpty);
        expect(await f.service.getStored('u1', 'm1'), isNull);
        expect(f.store.docs, isEmpty);
      },
    );

    test('pressing release again keeps publishedAt and does not stamp a new '
        'updatedAt on untouched reports', () async {
      final f = _Fixture();
      await f.service.publish(milestone: _milestone(), proposals: [_signed()]);

      f.now = _released.add(const Duration(days: 2));
      final again = await f.service.publish(
        milestone: _milestone(),
        proposals: [_signed()],
      );

      expect(again.single.publishedAt, _released);
      expect(again.single.updatedAt, _released);
      expect(again.single.isRepublished, isFalse);
      expect(f.store.docs['u1_m1']!['updatedAt'], _released.toIso8601String());
    });

    test(
      'returns every published report of the milestone, across partitions',
      () async {
        final f = _Fixture();
        await f.service.publish(
          milestone: _milestone(),
          proposals: [
            _signed(),
            _signed(uid: 'u2'),
          ],
        );

        final all = await f.service.getForMilestone('m1');
        expect(all.map((r) => r.uid).toSet(), {'u1', 'u2'});
        expect(await f.service.getForMilestone('other'), isEmpty);
      },
    );
  });

  // The student's own read (#151) — the only way a report leaves the
  // teacher's side.
  group('watchForUser', () {
    test('streams this student\'s released reports, newest report date '
        'first', () async {
      final f = _Fixture();
      await f.service.publish(
        milestone: _milestone(),
        proposals: [
          _signed(),
          _signed(uid: 'u2'),
        ],
      );
      await f.service.publish(
        milestone: _milestone(
          id: 'm2',
          title: 'Rapport 2',
          dueAt: DateTime.utc(2026, 12, 20),
        ),
        proposals: [_signed()],
      );

      final mine = await f.service.watchForUser('u1').first;

      expect(mine.map((r) => r.milestoneTitle), ['Rapport 2', 'Rapport 1']);
      expect(
        mine.every((r) => r.uid == 'u1'),
        isTrue,
        reason: 'a student reads their own partition and nothing else',
      );
      expect(mine.first.grade, 84);
    });

    test('a student with nothing released streams an empty list, not an '
        'error', () async {
      final f = _Fixture();
      await f.service.publish(
        milestone: _milestone(),
        proposals: [_signed(uid: 'u2')],
      );

      expect(await f.service.watchForUser('u1').first, isEmpty);
    });
  });

  group('republish', () {
    test(
      'overwrites the released copy with a fresh updatedAt and no history',
      () async {
        final f = _Fixture();
        await f.service.publish(
          milestone: _milestone(),
          proposals: [_signed()],
        );

        const afterTalk = 'Na ons gesprek: Sam had de opdracht wel begrepen.';
        f.now = _released.add(const Duration(days: 3));
        final republished = await f.service.republish(
          milestone: _milestone(),
          proposal: _signed(justification: afterTalk),
        );

        expect(republished!.justification, afterTalk);
        // §5 freezes the grade, not the sentence: the number did not move.
        expect(republished.grade, 84);
        expect(republished.publishedAt, _released, reason: 'first release');
        expect(republished.updatedAt, f.now);
        expect(republished.isRepublished, isTrue);
        // One doc, not two: no revision history.
        expect(f.store.docs.keys, ['u1_m1']);
        expect(f.store.docs['u1_m1']!['justification'], afterTalk);
      },
    );

    test('is a no-op for a student whose report was never released', () async {
      final f = _Fixture();

      final republished = await f.service.republish(
        milestone: _milestone(),
        proposal: _signed(justification: 'Herschreven voor de vrijgave.'),
      );

      expect(republished, isNull);
      expect(f.store.docs, isEmpty, reason: 'nothing leaks out before release');
    });
  });

  // #170: the account had no `reports` container. The read before the write
  // took the 404 for "not released yet", so release only failed at the
  // upsert, with a gateway message that named neither the container nor the
  // fix — and a rewrite after sign-off skipped the republish in silence.
  group('a `reports` container missing from the account (#170)', () {
    final containerMissing = isA<CosmosException>().having(
      (e) => e.isContainerNotFound,
      'isContainerNotFound',
      isTrue,
    );

    test('release fails naming the container, before any write', () async {
      final cosmos = UnprovisionedCosmos('reports');
      final service = PublishedReportService(container: cosmos.container);

      await expectLater(
        service.publish(milestone: _milestone(), proposals: [_signed()]),
        throwsA(containerMissing),
      );
      expect(cosmos.writes, isEmpty);
    });

    test('a rewrite after sign-off does not pass for "never released"', () {
      final cosmos = UnprovisionedCosmos('reports');
      final service = PublishedReportService(container: cosmos.container);

      expect(
        service.republish(milestone: _milestone(), proposal: _signed()),
        throwsA(containerMissing),
      );
    });
  });
}
