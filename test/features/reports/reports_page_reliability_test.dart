// The reliability line of the Reports detail pane (#173).
//
// "Stale: X LOs (never probed: Y). Exercises this period: 0 supervised, N at
// home." stood against every student while no supervision registry is
// bound — the shipped app until Anchor lands, where every turn is `home`
// by construction. The staleness half is a measurement and stays; the turn
// tally is one only once `SupervisionSource.isWired` says a registry stands
// behind it, and the pane shows it only then. Same rule #160 applied to the
// justification prompt; here it is the line the teacher reads. The counts
// themselves stay on the `grade_proposals` doc either way.
//
// The tally counts oefeningen, the teacher's word for them, and says so in
// both languages (#200): "Oefeningen deze periode", not "Beurten".
//
// The real page over the real services against in-memory Cosmos. The same
// pane in the real Windows app, reached through the sidebar, is
// `integration_test/flows/grade_proposal.dart`.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/features/reports/reports_page.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

const _teacher = AccountIdentity(
  oid: 't1',
  displayName: 'Tess Teacher',
  email: 'tess@example.com',
  firstName: 'Tess',
  lastName: 'Teacher',
  isTeacher: true,
);

class _SignedInTeacher extends AuthService {
  @override
  AccountIdentity? build() => _teacher;
}

/// The binding the shipped app gets once Anchor lands: a registry stands
/// behind it. What it answers per turn never matters here — that it is
/// *wired* does.
class _AnchorBound implements SupervisionSource {
  const _AnchorBound();

  @override
  bool get isWired => true;

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async => EvidenceProvenance.supervised;
}

const _uid = 'u1';
final DateTime _now = DateTime.now().toUtc();

Map<String, dynamic> _student() => {
  'id': _uid,
  'uid': _uid,
  'email': 'sam@example.com',
  'firstName': 'Sam',
  'lastName': 'Student',
  'targetGoal': 'Python',
  'mayUseGlobalKey': true,
  'className': '5A',
  'calibration': {
    'difficulty': 'medium',
    'recentAnswers': <String>[],
    'recentQuestionTypes': <String>[],
  },
};

Map<String, dynamic> _milestone() => {
  'id': 'm1',
  'type': 'milestone',
  'title': 'Rapport 1',
  'periodStart': _now.subtract(const Duration(days: 30)).toIso8601String(),
  'dueAt': _now.add(const Duration(days: 7)).toIso8601String(),
  'expectedDifficulty': 'medium',
  'subgoalIds': ['s1'],
  'coreLoKeys': ['s1/lo-print'],
  'updatedAt': _now.toIso8601String(),
};

/// A computed proposal as the batch leaves it, with both halves of the
/// reliability line filled in — including the "0 supervised, 14 at home"
/// tally an unwired binding produces for everyone.
Map<String, dynamic> _proposal() => {
  'id': '${_uid}_m1',
  'type': 'grade_proposal',
  'uid': _uid,
  'milestoneId': 'm1',
  'formulaVersion': '1.0.12',
  'computedAt': _now.toIso8601String(),
  'k': 1.0,
  'u': 0.5,
  'd': 0.5,
  'mEnd': 90.0,
  'mStart': 50.0,
  'g': 0.8,
  'proposal': 86,
  'coreTotal': 1,
  'coreCounted': 1,
  'extensionTotal': 1,
  'extensionMastered': 1,
  'masteredTotal': 2,
  'hardCount': 1,
  'staleLoCount': 2,
  'neverProbedCount': 1,
  'supervisedTurns': 0,
  'homeTurns': 14,
  'mStartSource': 'history',
  'justification': 'Sam beheerst de kern.',
  'justificationSource': 'ai',
};

void main() {
  /// Mounts the page signed in as a teacher, waits for the milestone to be
  /// picked and its proposal to load, and opens Sam's report.
  Future<void> mount(
    WidgetTester tester, {
    SupervisionSource? supervision,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    InMemoryCosmosClient({
      'accounts': InMemoryCosmos([_student()]),
      'milestones': InMemoryCosmos([_milestone()]),
      'grade_proposals': InMemoryCosmos([_proposal()]),
    }).install();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith(_SignedInTeacher.new),
          if (supervision != null)
            supervisionSourceProvider.overrideWithValue(supervision),
        ],
        child: localizedTestApp(
          const Scaffold(body: ReportsPage()),
          locale: locale,
        ),
      ),
    );
    // The account and milestone streams poll; the milestone is picked in a
    // post-frame callback and its proposals arrive one async hop later.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('reports-row-$_uid')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String reliability(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('reports-detail-reliability')))
      .data!;

  testWidgets('with no supervision registry bound the reliability line '
      'stops at the staleness counts', (tester) async {
    // The production binding: `NoSupervisionSource`, `isWired == false`.
    await mount(tester);

    expect(reliability(tester), 'Stale: 2 LOs (never probed: 1).');
    expect(find.textContaining('Exercises this period'), findsNothing);
    // The rest of the report is untouched.
    expect(find.text('Demonstrated at hard: 1 / 2 mastered'), findsOneWidget);
  });

  testWidgets('with a supervision registry bound the turn tally is back on '
      'the line', (tester) async {
    await mount(tester, supervision: const _AnchorBound());

    expect(
      reliability(tester),
      'Stale: 2 LOs (never probed: 1). '
      'Exercises this period: 0 supervised, 14 at home.',
    );
  });

  testWidgets('the Dutch line follows the same rule', (tester) async {
    await mount(tester, locale: const Locale('nl'));

    expect(reliability(tester), 'Verouderd: 2 leerdoelen (nooit bevraagd: 1).');
    expect(find.textContaining('onder toezicht'), findsNothing);
  });

  testWidgets('the Dutch tally counts oefeningen, the word the teacher uses '
      '(#200)', (tester) async {
    await mount(
      tester,
      supervision: const _AnchorBound(),
      locale: const Locale('nl'),
    );

    expect(
      reliability(tester),
      'Verouderd: 2 leerdoelen (nooit bevraagd: 1). '
      'Oefeningen deze periode: 0 onder toezicht, 14 thuis.',
    );
    expect(find.textContaining('Beurten'), findsNothing);
  });
}
