import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Progress.toMap carries id/uid/goalId/progress and stamps timestamps',
    () {
      final p = Progress(goalID: 'g-1', progress: 0.42);
      final map = p.toMap(uid: 'u-1');
      expect(map['id'], 'u-1_g-1');
      expect(map['uid'], 'u-1');
      expect(map['goalId'], 'g-1');
      expect(map['progress'], 0.42);
      expect(map['updatedAt'], isA<String>());
      expect(map['lastSessionAt'], isA<String>());
      // Dropped fields must not appear.
      expect(map.containsKey('difficulty'), isFalse);
      expect(map.containsKey('recentAnswers'), isFalse);
      expect(map.containsKey('recentConceptAttributions'), isFalse);
    },
  );

  test('Progress.fromCosmos reads the minimal shape', () {
    final p = Progress.fromCosmos({
      'id': 'u_g',
      'uid': 'u',
      'goalId': 'g',
      'progress': 0.5,
      'updatedAt': '2026-05-09T10:00:00Z',
      'lastSessionAt': '2026-05-09T10:00:00Z',
    });
    expect(p.goalID, 'g');
    expect(p.progress, 0.5);
    expect(p.updatedAt, isNotNull);
    expect(p.lastSessionAt, isNotNull);
  });
}
