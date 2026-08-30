import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress_reset.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'u1';
const _other = 'u2';

Map<String, dynamic> _goal(String id, String title, {String? parentId}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': 1000,
};

Map<String, dynamic> _progress(String uid, String goalId, double v) => {
  'id': '${uid}_$goalId',
  'uid': uid,
  'goalId': goalId,
  'progress': v,
};

Map<String, dynamic> _byGoal(String id, String uid, String goalId) => {
  'id': id,
  'uid': uid,
  'goalId': goalId,
};

Map<String, dynamic> _bySubgoal(String id, String uid, String subgoalId) => {
  'id': id,
  'uid': uid,
  'subgoalId': subgoalId,
};

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos progress;
  late InMemoryCosmos history;
  late InMemoryCosmos beliefs;
  late InMemoryCosmos turns;
  late List<StudentCalibration> calibrations;
  late ProgressReset reset;

  setUp(() {
    goals = InMemoryCosmos([
      _goal('r1', 'Loops'),
      _goal('s1', 'For', parentId: 'r1'),
      _goal('s2', 'While', parentId: 'r1'),
      _goal('r2', 'Functions'),
      _goal('s3', 'Def', parentId: 'r2'),
    ]);
    progress = InMemoryCosmos([
      _progress(_uid, 'r1', 0.75),
      _progress(_uid, 's1', 1.0),
      _progress(_uid, 's2', 0.5),
      _progress(_uid, 's3', 1.0),
      _progress(_other, 's1', 1.0),
    ]);
    history = InMemoryCosmos([
      _byGoal('h1', _uid, 's1'),
      _byGoal('h2', _uid, 's2'),
      _byGoal('h3', _other, 's1'),
    ]);
    beliefs = InMemoryCosmos([
      _bySubgoal('b1', _uid, 's1'),
      _bySubgoal('b2', _uid, 's2'),
      _bySubgoal('b3', _other, 's1'),
    ]);
    turns = InMemoryCosmos([
      _bySubgoal('t1', _uid, 's1'),
      _bySubgoal('t2', _uid, 's2'),
      _bySubgoal('t3', _other, 's1'),
    ]);
    calibrations = [];
    reset = ProgressReset(
      goals: GoalsService(container: goals.container),
      progress: ProgressService(
        container: progress.container,
        historyContainer: history.container,
        getUid: () => _uid,
      ),
      loBeliefs: LoBeliefsService(
        container: beliefs.container,
        getUid: () => _uid,
      ),
      turnHistory: TurnHistoryService(
        container: turns.container,
        getUid: () => _uid,
      ),
      setCalibration: (c) async => calibrations.add(c),
    );
  });

  test(
    'resetAll clears the current user only and resets calibration',
    () async {
      await reset.resetAll();

      expect(progress.docs.keys, ['${_other}_s1']);
      expect(history.docs.keys, ['h3']);
      expect(beliefs.docs.keys, ['b3']);
      expect(turns.docs.keys, ['t3']);
      expect(
        calibrations.single.difficulty,
        StudentCalibration.defaultDifficulty,
      );
    },
  );

  test(
    'resetGoal on a subgoal clears its docs and recomputes the root',
    () async {
      final s1 = Goal(id: 's1', title: 'For', parentId: 'r1', order: 1000);
      final n = await reset.resetGoal(s1);

      expect(n, 1);
      expect(progress['${_uid}_s1'], isNull);
      expect(progress['${_uid}_s2']!['progress'], 0.5);
      expect(progress['${_uid}_s3']!['progress'], 1.0);
      expect(progress['${_other}_s1'], isNotNull);
      // Root mean over (s1 = missing → 0, s2 = 0.5).
      expect(progress['${_uid}_r1']!['progress'], 0.25);
      expect(history.docs.keys, ['h2', 'h3']);
      expect(beliefs.docs.keys, ['b2', 'b3']);
      expect(turns.docs.keys, ['t2', 't3']);
      expect(calibrations, isEmpty);
    },
  );

  test('resetGoal on a root clears every child and the root cache', () async {
    final r1 = Goal(id: 'r1', title: 'Loops', order: 1000);
    final n = await reset.resetGoal(r1);

    expect(n, 2);
    expect(progress.docs.keys, ['${_uid}_s3', '${_other}_s1']);
    expect(history.docs.keys, ['h3']);
    expect(beliefs.docs.keys, ['b3']);
    expect(turns.docs.keys, ['t3']);
  });

  test('resetGoal tolerates a subgoal without any stored state', () async {
    final s3 = Goal(id: 's3', title: 'Def', parentId: 'r2', order: 1000);
    await reset.resetGoal(s3);
    await reset.resetGoal(s3);

    expect(progress['${_uid}_s3'], isNull);
    expect(progress['${_uid}_r2']!['progress'], 0.0);
  });
}
