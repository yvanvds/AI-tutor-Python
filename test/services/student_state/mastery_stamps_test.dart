// Issue #243 — the Leerpad counts what the grade reads: a learning
// objective is demonstrated when its `lo_beliefs` doc carries the one-way
// mastery stamp (`firstMasteredAt`, PUNTENFORMULE §2.2), not when its belief
// happens to stand high today. A subgoal's count is over its non-optional
// LOs as the curriculum lists them, so an optional LO and a belief on an LO
// that left the subgoal do not count. The provider reads the signed-in
// student's beliefs once.

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/mastery_stamps.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

final _at = DateTime.utc(2026, 10, 1, 9);

LearningObjective _lo(String id, {bool optional = false}) => LearningObjective(
  id: id,
  statement: 'Je kan $id.',
  kind: LoKind.apply,
  optional: optional,
);

LoBelief _belief(
  String subgoalId,
  String loId, {
  bool stamped = false,
  double alpha = 1,
  double beta = 1,
}) => LoBelief(
  subgoalId: subgoalId,
  loId: loId,
  alpha: alpha,
  beta: beta,
  lastUpdatedAt: _at,
  lastPositiveAtCalibratedAt: _at,
  firstMasteredAt: stamped ? _at : null,
);

final _variables = Goal(
  id: 's2',
  title: 'Variabelen',
  parentId: 'r1',
  order: 2000,
  objectives: [
    _lo('lo-var'),
    _lo('lo-cast'),
    _lo('lo-name'),
    _lo('lo-extra', optional: true),
  ],
);

void main() {
  group('MasteryStamps', () {
    test('counts the stamped non-optional LOs of the subgoal', () {
      final stamps = MasteryStamps.fromBeliefs([
        _belief('s2', 'lo-var', stamped: true),
        _belief('s2', 'lo-cast', stamped: true),
        _belief('s2', 'lo-name'),
      ]);

      final count = stamps.countFor(_variables);
      expect(count, const DemonstratedCount(demonstrated: 2, total: 3));
      expect(count.fraction, closeTo(2 / 3, 1e-9));
      expect(stamps.isDemonstrated('s2', 'lo-var'), isTrue);
      expect(stamps.isDemonstrated('s2', 'lo-name'), isFalse);
    });

    test('a belief that meets mastery today but has no stamp is not '
        'demonstrated, as the grade reads it', () {
      final stamps = MasteryStamps.fromBeliefs([
        // (9, 1): μ 0,90 on evidence 10, calibrated positive on record —
        // mastered by the belief, but never stamped.
        _belief('s2', 'lo-var', alpha: 9, beta: 1),
      ]);
      expect(stamps.isDemonstrated('s2', 'lo-var'), isFalse);
      expect(
        stamps.countFor(_variables),
        const DemonstratedCount(demonstrated: 0, total: 3),
      );
    });

    test('an optional LO, a belief on an LO no longer in the subgoal and '
        'one on the same LO id in another subgoal do not count', () {
      final stamps = MasteryStamps.fromBeliefs([
        _belief('s2', 'lo-extra', stamped: true),
        _belief('s2', 'lo-gone', stamped: true),
        _belief('s9', 'lo-var', stamped: true),
      ]);
      expect(
        stamps.countFor(_variables),
        const DemonstratedCount(demonstrated: 0, total: 3),
      );
      // The optional LO itself is still known as demonstrated, for the list.
      expect(stamps.isDemonstrated('s2', 'lo-extra'), isTrue);
    });

    test('a subgoal without non-optional LOs has nothing to count', () {
      final empty = Goal(id: 's5', title: 'Leeg', parentId: 'r1', order: 5);
      final count = const MasteryStamps.empty().countFor(empty);
      expect(count.total, 0);
      expect(count.fraction, isNull);
    });
  });

  group('masteryStampsProvider', () {
    test('reads the signed-in student\'s beliefs from `lo_beliefs`, only '
        'theirs', () async {
      final store = InMemoryCosmos([
        _belief('s2', 'lo-var', stamped: true).toMap(uid: 'me'),
        _belief('s2', 'lo-cast').toMap(uid: 'me'),
        _belief('s2', 'lo-cast', stamped: true).toMap(uid: 'someone-else'),
      ]);
      final container = ProviderContainer(
        overrides: [
          loBeliefsServiceProvider.overrideWithValue(
            LoBeliefsService(container: store.container, getUid: () => 'me'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final stamps = await container.read(masteryStampsProvider.future);
      expect(
        stamps.countFor(_variables),
        const DemonstratedCount(demonstrated: 1, total: 3),
      );
      expect(stamps.isDemonstrated('s2', 'lo-cast'), isFalse);
    });

    test('without a signed-in student the read fails, and the Leerpad gets '
        'no stamps', () async {
      final container = ProviderContainer(
        overrides: [
          loBeliefsServiceProvider.overrideWithValue(
            LoBeliefsService(
              container: InMemoryCosmos().container,
              getUid: () => null,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(masteryStampsProvider, (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        container.read(masteryStampsProvider.future),
        throwsStateError,
      );
      expect(container.read(masteryStampsProvider).valueOrNull, isNull);
    });
  });
}
