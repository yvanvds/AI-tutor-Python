import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mcQuestion includes target_los when provided', () {
    final raw = QuestionFormatter.mcQuestion(
      QuestionDifficulty.medium,
      targetLOs: const [
        LearningObjective(
          id: 'predict_branch',
          statement: 'pb',
          kind: LoKind.predict,
        ),
      ],
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    expect(m['request_type'], 'multiple_choice');
    expect(m['difficulty'], 'medium');
    expect(m['target_los'], hasLength(1));
    expect((m['target_los'] as List).first['kind'], 'predict');
  });

  test('mcqAnswer carries goal_scope_los', () {
    final raw = QuestionFormatter.mcqAnswer(
      'A',
      targetLOs: const [
        LearningObjective(id: 't', statement: 't', kind: LoKind.apply),
      ],
      goalScopeLOs: [
        (
          subgoalId: 'sub-1',
          lo: const LearningObjective(
            id: 'l1',
            statement: 'one',
            kind: LoKind.recall,
          ),
        ),
        (
          subgoalId: 'sub-2',
          lo: const LearningObjective(
            id: 'l2',
            statement: 'two',
            kind: LoKind.reason,
          ),
        ),
      ],
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    expect(m['request_type'], 'mcq_answer');
    expect(m['answer'], 'A');
    expect(m['target_los'], hasLength(1));
    expect(m['goal_scope_los'], hasLength(2));
    expect((m['goal_scope_los'] as List).last['subgoalId'], 'sub-2');
  });

  test('grading payloads name the subgoal of the target LOs when told '
      '(#102); question payloads never do', () {
    const lo = LearningObjective(id: 't', statement: 't', kind: LoKind.apply);
    final graded = jsonDecode(
      QuestionFormatter.submitCode(
        'x = 1',
        targetLOs: const [lo],
        targetSubgoalId: 's0',
      ),
    ) as Map<String, dynamic>;
    expect((graded['target_los'] as List).single['subgoalId'], 's0');

    final untold = jsonDecode(
      QuestionFormatter.submitCode('x = 1', targetLOs: const [lo]),
    ) as Map<String, dynamic>;
    expect(
      (untold['target_los'] as List).single.containsKey('subgoalId'),
      isFalse,
    );

    final question = jsonDecode(
      QuestionFormatter.completeCodeQuestion(
        QuestionDifficulty.easy,
        targetLOs: const [lo],
      ),
    ) as Map<String, dynamic>;
    expect(
      (question['target_los'] as List).single.containsKey('subgoalId'),
      isFalse,
    );
  });

  test('writeCodeQuestion omits target_los key when none', () {
    final raw = QuestionFormatter.writeCodeQuestion(QuestionDifficulty.hard);
    final m = jsonDecode(raw) as Map<String, dynamic>;
    expect(m.containsKey('target_los'), isFalse);
    expect(m['difficulty'], 'hard');
  });
}
