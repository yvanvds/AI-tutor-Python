import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Goal subgoal({String teaching = 'Tip A'}) => Goal(
        id: 'sub-1',
        title: 'Loops',
        parentId: 'root-1',
        order: 1000,
        teachingTips: [teaching],
        objectives: const [
          LearningObjective(
            id: 'iter_fixed_count',
            statement: 'You can iterate N times.',
            kind: LoKind.apply,
          ),
        ],
      );

  Goal root() => Goal(id: 'root-1', title: 'Iteration', order: 0);

  Instruction makeInstruction(String id, Map<String, String> sections) =>
      Instruction(
        id: id,
        sections: sections,
        updatedAt: DateTime.utc(2026, 5, 9),
      );

  test('substitutes new tags and drops {known concepts}', () async {
    final selection = GoalSelectionState(
      selectedRoot: root(),
      selectedChild: subgoal(),
    );
    final out = await InstructionGenerator().generateInstructions(
      ChatRequestType.mcQuestion,
      goalSelection: selection,
      cachedInstructions: [
        makeInstruction('alwaysInclude', {
          'main': 'Goal {goal} - subgoal {subgoal}; tips: {teachingTips}; '
              'known:[{known concepts}]',
        }),
        makeInstruction('mcQuestion', {
          'main': 'Probe: {targetLOs}\nScope: {goalScopeLOs}',
        }),
      ],
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
      targetLOs: const [
        LearningObjective(
          id: 'iter_fixed_count',
          statement: 'You can iterate N times.',
          kind: LoKind.apply,
        ),
      ],
      goalScopeLOs: [
        (
          subgoalId: 'sub-1',
          lo: const LearningObjective(
            id: 'iter_fixed_count',
            statement: 'You can iterate N times.',
            kind: LoKind.apply,
          ),
        ),
      ],
    );

    expect(out, contains('Goal Iteration - subgoal Loops'));
    expect(out, contains('tips: Tip A'));
    // {known concepts} resolves to empty.
    expect(out, contains('known:[]'));
    expect(out, contains('iter_fixed_count'));
    expect(out, contains('You can iterate N times.'));
    // Envelope contract is prepended.
    expect(out, contains('RESPONSE FORMAT — STRICT.'));
  });

  test('returns empty when no goal selection', () async {
    final out = await InstructionGenerator().generateInstructions(
      ChatRequestType.mcQuestion,
      goalSelection: const GoalSelectionState(),
      cachedInstructions: const [],
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
    );
    expect(out, isEmpty);
  });
}
