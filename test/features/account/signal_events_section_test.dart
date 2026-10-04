// The teacher's signal-event list in the student drawer (CONDUCTOR_POLICY
// §8.2) shows a provenance gap (#107) in words: the LO by its statement, how
// many of its direct signals were positive at home and in the lessons after,
// and over how long — an audit one in amber below the strong ones, a strong
// one in red and counted by the acknowledge button.

import 'package:ai_tutor_python/features/account/detail/signal_events_section.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/provenance_gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
