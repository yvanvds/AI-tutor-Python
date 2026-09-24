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

  test('mcqAnswer carries the answer key as correct_option when given, and '
      'nothing of it otherwise (#197)', () {
    final keyed = jsonDecode(
      QuestionFormatter.mcqAnswer('11', correctOption: '2'),
    ) as Map<String, dynamic>;
    expect(keyed['answer'], '11');
    expect(keyed['correct_option'], '2');

    final plain =
        jsonDecode(QuestionFormatter.mcqAnswer('11')) as Map<String, dynamic>;
    expect(plain.containsKey('correct_option'), isFalse);
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

  test('every question request carries the recent questions, oldest first, '
      'and omits the block when there are none (#184)', () {
    const recent = [
      'complete_code | lo-print | Vul aan. `print(___)`',
      'multiple_choice | lo-var | Wat toont dit? `x = 3; print(x)`',
    ];
    final builders = <String, String Function(List<String> recentQuestions)>{
      'socratic_question': (r) => QuestionFormatter.socraticQuestion(
        QuestionDifficulty.easy,
        recentQuestions: r,
      ),
      'multiple_choice': (r) => QuestionFormatter.mcQuestion(
        QuestionDifficulty.easy,
        recentQuestions: r,
      ),
      'explain_code': (r) => QuestionFormatter.explainCodeQuestion(
        QuestionDifficulty.easy,
        recentQuestions: r,
      ),
      'complete_code': (r) => QuestionFormatter.completeCodeQuestion(
        QuestionDifficulty.easy,
        recentQuestions: r,
      ),
      'write_code': (r) => QuestionFormatter.writeCodeQuestion(
        QuestionDifficulty.easy,
        recentQuestions: r,
      ),
    };
    for (final MapEntry(key: type, value: build) in builders.entries) {
      final withRecent = jsonDecode(build(recent)) as Map<String, dynamic>;
      expect(withRecent['request_type'], type);
      expect(withRecent['recent_questions'], recent, reason: type);

      final without = jsonDecode(build(const [])) as Map<String, dynamic>;
      expect(without.containsKey('recent_questions'), isFalse, reason: type);
    }
  });

  test('contentQuestion carries the question and the page as text, and '
      'nothing a grader would read (#132)', () {
    const page = 'Zo toon je iets op het scherm.\n\n```\nprint(1, 2)\n```';
    final raw = QuestionFormatter.contentQuestion(
      'Waarom staat er een komma?',
      contentTitle: 'Print',
      contentText: page,
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    expect(m, {
      'request_type': 'content_question',
      'question': 'Waarom staat er een komma?',
      'content_title': 'Print',
      'content': page,
    });
    expect(m.containsKey('target_los'), isFalse);
    expect(m.containsKey('goal_scope_los'), isFalse);
    expect(m.containsKey('difficulty'), isFalse);
    expect(m.containsKey('code'), isFalse);
  });
}
