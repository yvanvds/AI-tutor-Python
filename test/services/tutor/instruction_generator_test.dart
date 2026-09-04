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
          'main':
              'Goal {goal} - subgoal {subgoal}; tips: {teachingTips}; '
              'known:[{known concepts}]',
        }),
        makeInstruction('mcQuestion', {
          'main': 'Probe: {targetLOs}\nScope: {goalScopeLOs}',
        }),
      ],
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
      languageCode: 'nl',
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

  test('a subgoal override replaces {subgoal} and {teachingTips} in both '
      'the always-include and the type-specific sections (#102)', () async {
    final selection = GoalSelectionState(
      selectedRoot: root(),
      selectedChild: subgoal(),
    );
    final older = Goal(
      id: 'sub-0',
      title: 'Print',
      parentId: 'root-1',
      order: 0,
      teachingTips: const ['Tip P'],
    );
    final out = await InstructionGenerator().generateInstructions(
      ChatRequestType.completeCodeQuestion,
      goalSelection: selection,
      cachedInstructions: [
        makeInstruction('alwaysInclude', {
          'main': 'always: {goal} / {subgoal} / {teachingTips}',
        }),
        makeInstruction('completeCodeQuestion', {
          'main': 'type: {subgoal} / {teachingTips}',
        }),
      ],
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
      languageCode: 'nl',
      subgoalOverride: older,
    );
    expect(out, contains('always: Iteration / Print / Tip P'));
    expect(out, contains('type: Print / Tip P'));
    expect(out, isNot(contains('Loops')));
  });

  test('returns empty when no goal selection', () async {
    final out = await InstructionGenerator().generateInstructions(
      ChatRequestType.mcQuestion,
      goalSelection: const GoalSelectionState(),
      cachedInstructions: const [],
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
      languageCode: 'nl',
    );
    expect(out, isEmpty);
  });

  group('output-language directive (#117)', () {
    Future<String> generate(String languageCode) =>
        InstructionGenerator().generateInstructions(
          ChatRequestType.mcQuestion,
          goalSelection: GoalSelectionState(
            selectedRoot: root(),
            selectedChild: subgoal(),
          ),
          cachedInstructions: [
            // A teacher-authored body in Dutch, as the real ones are.
            makeInstruction('alwaysInclude', {
              'main': 'Stel een vraag over {subgoal}.',
            }),
            makeInstruction('mcQuestion', {'main': 'Geef vier opties.'}),
          ],
          fetchInstructions: () async => const [],
          fetchRootGoals: () async => const [],
          languageCode: languageCode,
        );

    test('names English for an English student', () async {
      final out = await generate('en');
      expect(out, contains('OUTPUT LANGUAGE — STRICT.'));
      expect(out, contains('Write all student-facing text in English'));
      expect(out, isNot(contains('Dutch (Nederlands)')));
    });

    test('names Dutch for a Dutch student', () async {
      final out = await generate('nl');
      expect(
        out,
        contains('Write all student-facing text in Dutch (Nederlands)'),
      );
    });

    test(
      'falls back to English for a language the app has no name for',
      () async {
        expect(
          await generate('fr'),
          contains('Write all student-facing text in English'),
        );
      },
    );

    test('comes after the teacher-authored bodies it must override', () async {
      final out = await generate('en');
      expect(
        out.indexOf('OUTPUT LANGUAGE'),
        greaterThan(out.indexOf('Geef vier opties.')),
        reason: 'the directive must be the last word in the system prompt',
      );
      expect(out.trimRight(), endsWith('you show the student.'));
    });

    test('exempts the machine half of the contract from translation', () async {
      final out = await generate('en');
      expect(out, contains('Never translate the machine parts'));
      expect(out, contains('learning-objective ids'));
      // The envelope contract itself is still intact above it.
      expect(out, contains('RESPONSE FORMAT — STRICT.'));
    });
  });
}
