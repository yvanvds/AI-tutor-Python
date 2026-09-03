// `Milestone` (#99): the Cosmos round trip, the composite LO key, and the
// conservative parse of a partial doc.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

void main() {
  final m = Milestone(
    id: 'm1',
    title: 'Rapport 1',
    periodStart: DateTime.utc(2026, 9, 1),
    dueAt: DateTime.utc(2026, 10, 15),
    expectedDifficulty: QuestionDifficulty.hard,
    subgoalIds: const ['s1', 's2'],
    coreLoKeys: {Milestone.loKey('s1', 'lo-a'), Milestone.loKey('s2', 'lo-b')},
  );

  test('round-trips through the doc map', () {
    final doc = m.toMap();
    expect(doc['type'], 'milestone');
    expect(doc['coreLoKeys'], ['s1/lo-a', 's2/lo-b']);
    final back = Milestone.fromCosmos(doc);
    expect(back.id, 'm1');
    expect(back.title, 'Rapport 1');
    expect(back.periodStart, DateTime.utc(2026, 9, 1));
    expect(back.dueAt, DateTime.utc(2026, 10, 15));
    expect(back.expectedDifficulty, QuestionDifficulty.hard);
    expect(back.subgoalIds, ['s1', 's2']);
    expect(back.isCore('s1', 'lo-a'), isTrue);
    expect(back.isCore('s1', 'lo-b'), isFalse);
    expect(back.isCore('s2', 'lo-b'), isTrue);
  });

  test('LO ids are only unique within a subgoal, so the key carries both', () {
    expect(Milestone.loKey('s1', 'lo'), isNot(Milestone.loKey('s2', 'lo')));
  });

  test('a partial doc parses with safe defaults', () {
    final back = Milestone.fromCosmos({'id': 'x', 'expectedDifficulty': '??'});
    expect(back.title, '');
    expect(back.expectedDifficulty, QuestionDifficulty.medium);
    expect(back.subgoalIds, isEmpty);
    expect(back.coreLoKeys, isEmpty);
  });

  test('the service lists milestones earliest due date first', () async {
    final store = InMemoryCosmos([
      m.copyWith(dueAt: DateTime.utc(2026, 12, 20)).toMap()..['id'] = 'late',
      m.toMap(),
    ]);
    final svc = MilestoneService(container: store.container);
    final all = await svc.getAllOnce();
    expect(all.map((x) => x.id), ['m1', 'late']);

    await svc.delete('late');
    expect((await svc.getAllOnce()).map((x) => x.id), ['m1']);
    expect((await svc.getById('m1'))?.title, 'Rapport 1');
  });
}
