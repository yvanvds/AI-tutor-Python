import 'package:ai_tutor_python/services/status_report/status_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusReport.toMap', () {
    test('produces composite id and all required fields', () {
      final report = StatusReport(goalID: 'goal-1', statusReport: 'On track');
      final map = report.toMap(uid: 'user-1');
      expect(map['id'], 'user-1_goal-1');
      expect(map['uid'], 'user-1');
      expect(map['goalId'], 'goal-1');
      expect(map['statusReport'], 'On track');
      expect(map['updatedAt'], isA<String>());
    });

    test('id uses uid and goalID', () {
      final report = StatusReport(goalID: 'g2', statusReport: 'Behind');
      final map = report.toMap(uid: 'alice');
      expect(map['id'], 'alice_g2');
    });
  });
}
