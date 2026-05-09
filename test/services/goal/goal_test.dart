import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Goal.fromCosmos parses typed objectives', () {
    final g = Goal.fromCosmos({
      'id': 'sub-1',
      'title': 'Use if/else',
      'parentId': 'root-1',
      'order': 1000,
      'objectives': [
        {
          'id': 'predict_branch',
          'statement': 'You can predict which branch runs.',
          'kind': 'predict',
          'weight': 1.5,
          'optional': false,
        },
        {
          'id': 'write_if_else',
          'statement': 'You can write a basic if/else.',
          'kind': 'apply',
        },
      ],
    });
    expect(g.objectives, hasLength(2));
    expect(g.objectives.first.id, 'predict_branch');
    expect(g.objectives.first.kind, LoKind.predict);
    expect(g.objectives.first.weight, 1.5);
    expect(g.objectives.last.kind, LoKind.apply);
    // Defaults applied.
    expect(g.objectives.last.weight, 1.0);
    expect(g.objectives.last.optional, false);
  });

  test('Goal.toMap serialises objectives back to maps', () {
    final g = Goal(
      id: 's',
      title: 't',
      order: 0,
      objectives: const [
        LearningObjective(
          id: 'lo1',
          statement: 's1',
          kind: LoKind.recall,
        ),
      ],
    );
    final m = g.toMap();
    expect(m['objectives'], isA<List>());
    expect((m['objectives'] as List).first, isA<Map>());
    expect((m['objectives'] as List).first['kind'], 'recall');
  });
}
