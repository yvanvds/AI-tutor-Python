import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Goal.toMap', () {
    test('serializes all fields', () {
      final goal = Goal(
        id: 'g1',
        title: 'Loops',
        description: 'For loops in Python',
        parentId: 'root',
        order: 3,
        optional: true,
        suggestions: ['try while', 'try for'],
        knownConcepts: ['variables'],
      );
      final map = goal.toMap();
      expect(map['title'], 'Loops');
      expect(map['description'], 'For loops in Python');
      expect(map['parentId'], 'root');
      expect(map['order'], 3);
      expect(map['optional'], isTrue);
      expect(map['suggestions'], ['try while', 'try for']);
      expect(map['knownConcepts'], ['variables']);
    });

    test('serializes null optional fields', () {
      final goal = Goal(id: 'g2', title: 'Test', order: 0);
      final map = goal.toMap();
      expect(map['description'], isNull);
      expect(map['parentId'], isNull);
      expect(map['optional'], isFalse);
      expect(map['suggestions'], isEmpty);
      expect(map['knownConcepts'], isEmpty);
    });
  });
}
