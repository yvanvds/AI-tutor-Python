// The teacher's signal-event list in the student drawer (CONDUCTOR_POLICY
// §8.2) shows a provenance gap (#107) in words: the LO by its statement, how
// many of its direct signals were positive at home and in the lessons after,
// and over how long — an audit one in amber below the strong ones, a strong
// one in red and counted by the acknowledge button. A stuck student (#229):
// the subgoal by its title, since when, how many of the last answers were
// not right and the LO asked most with its μ. A run of lost grades (#229):
// how many in a row, and on which LO.

import 'package:ai_tutor_python/features/account/detail/signal_events_section.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/no_progress.dart';
import 'package:ai_tutor_python/services/supervision/provenance_gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

final _goals = [
  Goal(
    id: 's1',
    title: 'Print',
    parentId: 'r1',
    order: 1000,
    objectives: const [
      LearningObjective(
        id: 'lo-print',
        statement: 'Use print() to show text',
        kind: LoKind.apply,
      ),
    ],
  ),
];

TurnSignalEvent _gap({
  String loId = 'lo-print',
  TurnSignalEventSeverity severity = TurnSignalEventSeverity.audit,
}) => ProvenanceGap(
  subgoalId: 's1',
  loId: loId,
  homeSignals: 3,
  homePositive: 3,
  supervisedSignals: 4,
  supervisedPositive: 1,
  severity: severity,
).toEvent();

/// Stuck on "Print" since [since] (local 11:20 by default).
TurnSignalEvent _stuck({String? loId = 'lo-print', DateTime? since}) =>
    NoProgress(
      subgoalId: 's1',
      since: since ?? DateTime(2026, 10, 2, 11, 20),
      minutes: 33,
      oefeningen: 9,
      answers: 10,
      notRight: 7,
      calibration: QuestionDifficulty.medium,
      loId: loId,
      mean: loId == null ? null : 0.6875,
    ).toEvent();

/// A third grade in a row lost on lo-print, as the conductor writes it.
const _lostRun = TurnSignalEvent(
  kind: TurnSignalEventKind.targetSignalLost,
  severity: TurnSignalEventSeverity.strong,
  details: {
    'subgoalId': 's1',
    'loId': 'lo-print',
    'signal': 'positive',
    'strength': 'strong',
    'activeRootId': 'r0',
    'fallback': false,
    'run': 3,
  },
);

void main() {
  late InMemoryCosmos store;

  Future<void> mount(
    WidgetTester tester,
    List<TurnSignalEvent> events, {
    Locale locale = const Locale('en'),
  }) async {
    store = InMemoryCosmos();
    final turns = TurnHistoryService(
      container: store.container,
      getUid: () => 'u1',
    );
    for (final (i, e) in events.indexed) {
      await turns.appendAudit(
        subgoalId: 's1',
        event: e,
        at: DateTime.utc(2026, 10, 2, 10, i),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [turnHistoryServiceProvider.overrideWithValue(turns)],
        child: localizedTestApp(
          Scaffold(
            body: SingleChildScrollView(
              child: SignalEventsSection(uid: 'u1', goals: _goals),
            ),
          ),
          locale: locale,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('an audit gap names the LO and the two counts, and is not '
      'counted for acknowledgement', (tester) async {
    await mount(tester, [_gap()]);

    expect(find.text('Class work contradicts home work'), findsOneWidget);
    expect(
      find.textContaining(
        'Use print() to show text: at home 3 of 3 positive, in class '
        'afterwards 1 of 4 (last 42 days)',
      ),
      findsOneWidget,
    );
    // The acknowledge button counts strong events only.
    expect(find.text('Acknowledge (0)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('in Dutch', (tester) async {
    await mount(tester, [_gap()], locale: const Locale('nl'));

    expect(find.text('De les spreekt het thuiswerk tegen'), findsOneWidget);
    expect(
      find.textContaining(
        'Use print() to show text: thuis 3 van 3 positief, in de les daarna '
        '1 van 4 (laatste 42 dagen)',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('an LO the curriculum no longer has is shown by its id', (
    tester,
  ) async {
    await mount(tester, [_gap(loId: 'lo-gone')]);

    expect(
      find.textContaining('lo-gone: at home 3 of 3 positive'),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('a strong gap is listed first, in red, and counted for '
      'acknowledgement', (tester) async {
    await mount(tester, [
      TurnSignalEvent.of(TurnSignalEventKind.cascadeHalt),
      _gap(severity: TurnSignalEventSeverity.strong),
    ]);

    expect(find.text('Acknowledge (1)'), findsOneWidget);
    final gapRow = tester.getTopLeft(
      find.text('Class work contradicts home work'),
    );
    final auditRow = tester.getTopLeft(find.text('Cascade halt (audit)'));
    expect(gapRow.dy, lessThan(auditRow.dy));

    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .map((d) => d.color)
        .toList();
    expect(dots, [Colors.red.shade400, Colors.amber.shade600]);

    await unmount(tester);
  });

  testWidgets('a stuck student: the subgoal by its title, since when, the '
      'answers not right and the LO asked most with its μ; strong', (
    tester,
  ) async {
    await mount(tester, [_stuck()]);

    expect(find.text('Stuck without progress'), findsOneWidget);
    expect(
      find.textContaining(
        'Print since 11:20 (33 min): 7 of the last 10 answers not right, '
        'most asked: Use print() to show text (μ 0.69)',
      ),
      findsOneWidget,
    );
    expect(find.text('Acknowledge (1)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a stuck student, in Dutch', (tester) async {
    await mount(tester, [_stuck()], locale: const Locale('nl'));

    expect(find.text('Loopt vast'), findsOneWidget);
    expect(
      find.textContaining(
        'Print sinds 11:20 (33 min): 7 van de laatste 10 antwoorden niet '
        'juist, meest gevraagd: Use print() to show text (μ 0,69)',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('"since" is on the clock of the teacher', (tester) async {
    final since = DateTime.utc(2026, 10, 2, 9, 5);
    await mount(tester, [_stuck(since: since)]);

    final clock = DateFormat.Hm('en').format(since.toLocal());
    expect(find.textContaining('Print since $clock (33 min)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('without an LO asked, the line ends at the answers', (
    tester,
  ) async {
    await mount(tester, [_stuck(loId: null)]);

    expect(
      find.textContaining('7 of the last 10 answers not right'),
      findsOneWidget,
    );
    expect(find.textContaining('most asked'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a run of lost grades says how many in a row and on which LO; '
      'one lost grade keeps its first details', (tester) async {
    await mount(tester, [
      TurnSignalEvent.of(
        TurnSignalEventKind.targetSignalLost,
        details: {'subgoalId': 's1', 'loId': 'lo-print'},
      ),
      _lostRun,
    ]);

    expect(find.text('Grade on the asked LO lost'), findsNWidgets(2));
    expect(
      find.textContaining(
        '3 questions in a row without a grade on the LO they asked about, '
        'the last on Use print() to show text',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('subgoalId: s1 · loId: lo-print'),
      findsOneWidget,
    );
    expect(find.text('Acknowledge (1)'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a run of lost grades, in Dutch', (tester) async {
    await mount(tester, [_lostRun], locale: const Locale('nl'));

    expect(
      find.text('Oordeel op het gevraagde leerdoel verloren'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '3 vragen op rij zonder oordeel op het leerdoel dat ze vroegen, de '
        'laatste op Use print() to show text',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });
}
