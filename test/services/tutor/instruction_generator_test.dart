// 1B.1 — Tests `InstructionGenerator.generateInstructions`. The generator
// pulls goal/instruction state through `DataService.goals` /
// `DataService.instructions` (i.e. the `get_it` locator), so the test
// pattern is: register `MockGoalsService` / `MockInstructionsService` under
// the *interface* type, plumb real `ValueNotifier`s through stubbed getters
// for the four selection notifiers, then drive `generateInstructions` with
// fixture `Instruction` lists and verify the rendered string.
//
// What's verified per TESTING_PLAN.md:
// - `_replaceTags` substitutes `{goal}`, `{subgoal}`, `{suggestions}`,
//   `{known concepts}` case-insensitively and tolerates whitespace inside
//   braces (`{ Goal }`).
// - Per-type instructions come first, `alwaysInclude` is appended last.
// - Mastered-concepts loop stops at the first goal whose
//   `order >= target.order` (so the target's own concepts are NOT
//   considered mastered).
// - Empty string when no goal is selected.

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

void main() {
  late MockGoalsService goals;
  late MockInstructionsService instructions;

  late ValueNotifier<Goal?> selectedRoot;
  late ValueNotifier<Goal?> selectedChild;
  late ValueNotifier<Goal?> preferredRoot;
  late ValueNotifier<Goal?> preferredChild;

  Goal makeGoal(
    String id, {
    String? title,
    int order = 1000,
    List<String> suggestions = const [],
    List<String> knownConcepts = const [],
  }) =>
      Goal(
        id: id,
        title: title ?? id,
        order: order,
        suggestions: suggestions,
        knownConcepts: knownConcepts,
      );

  setUp(() {
    goals = MockGoalsService();
    instructions = MockInstructionsService();

    selectedRoot = ValueNotifier<Goal?>(null);
    selectedChild = ValueNotifier<Goal?>(null);
    preferredRoot = ValueNotifier<Goal?>(null);
    preferredChild = ValueNotifier<Goal?>(null);

    when(() => goals.selectedRootGoal).thenReturn(selectedRoot);
    when(() => goals.selectedChildGoal).thenReturn(selectedChild);
    when(() => goals.preferredRootGoal).thenReturn(preferredRoot);
    when(() => goals.preferredChildGoal).thenReturn(preferredChild);

    when(() => goals.getRootGoalsOnce()).thenAnswer((_) async => <Goal>[]);
    when(() => instructions.getAll())
        .thenAnswer((_) async => <Instruction>[]);

    registerMock<GoalsService>(goals);
    registerMock<InstructionsService>(instructions);
  });

  tearDown(() async {
    await resetLocator();
    selectedRoot.dispose();
    selectedChild.dispose();
    preferredRoot.dispose();
    preferredChild.dispose();
  });

  group('generateInstructions — guard clauses', () {
    test('no selected root goal → empty string', () async {
      selectedChild.value = makeGoal('child');
      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, '');
      verifyNever(() => instructions.getAll());
    });

    test('no selected child goal → empty string', () async {
      selectedRoot.value = makeGoal('root');
      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, '');
      verifyNever(() => instructions.getAll());
    });
  });

  group('generateInstructions — section selection & ordering', () {
    test('per-type sections come first, alwaysInclude appended last',
        () async {
      selectedRoot.value = makeGoal('root');
      selectedChild.value = makeGoal('child');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'alwaysInclude',
            sections: {'rules': 'ALWAYS-RULES'},
          ),
          Instruction(
            id: 'socraticQuestion',
            sections: {'intro': 'TYPE-INTRO', 'body': 'TYPE-BODY'},
          ),
          // An unrelated id should be ignored.
          Instruction(
            id: 'mcQuestion',
            sections: {'noise': 'IGNORED'},
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);

      // Per-type sections render first (in map iteration order), then
      // alwaysInclude. The unrelated id contributes nothing.
      expect(out, 'TYPE-INTRO\nTYPE-BODY\nALWAYS-RULES\n');
      expect(out, isNot(contains('IGNORED')));
    });

    test('only alwaysInclude present → output is just the alwaysInclude '
        'sections', () async {
      selectedRoot.value = makeGoal('root');
      selectedChild.value = makeGoal('child');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'alwaysInclude',
            sections: {'a': 'ALWAYS'},
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.requestHint);
      expect(out, 'ALWAYS\n');
    });

    test('no matching id at all → empty string', () async {
      selectedRoot.value = makeGoal('root');
      selectedChild.value = makeGoal('child');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(id: 'somethingElse', sections: {'x': 'X'}),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, '');
    });
  });

  group('generateInstructions — _replaceTags', () {
    test('substitutes {goal}, {subgoal}, {suggestions}, {known concepts}',
        () async {
      selectedRoot.value = makeGoal('root', title: 'Lussen');
      selectedChild.value = makeGoal(
        'child',
        title: 'For-loop',
        suggestions: ['s1', 's2'],
      );

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'socraticQuestion',
            sections: {
              't': 'goal={goal} sub={subgoal} sug={suggestions} '
                  'known={known concepts}',
            },
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      // No mastered concepts because the only root goal IS the target —
      // the loop short-circuits before adding anything.
      expect(out, 'goal=Lussen sub=For-loop sug=s1\ns2 known=\n');
    });

    test('case-insensitive and tolerant of whitespace inside braces',
        () async {
      selectedRoot.value = makeGoal('root', title: 'GOAL-TITLE');
      selectedChild.value = makeGoal('child', title: 'SUB-TITLE');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'socraticQuestion',
            sections: {
              't': '{ Goal } / {GOAL} / { goal} / {goal } / { subGoal }',
            },
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(
        out,
        'GOAL-TITLE / GOAL-TITLE / GOAL-TITLE / GOAL-TITLE / SUB-TITLE\n',
      );
    });

    test('preferredRootGoal / preferredChildGoal override the selected pair '
        'for the per-type sections', () async {
      selectedRoot.value = makeGoal('selRoot', title: 'SEL-ROOT');
      selectedChild.value = makeGoal('selChild', title: 'SEL-CHILD');
      preferredRoot.value = makeGoal('prefRoot', title: 'PREF-ROOT');
      preferredChild.value = makeGoal('prefChild', title: 'PREF-CHILD');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'socraticQuestion',
            sections: {'t': 'goal={goal} sub={subgoal}'},
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, 'goal=PREF-ROOT sub=PREF-CHILD\n');
    });
  });

  group('generateInstructions — mastered concepts', () {
    test('only goals with order < target.order contribute concepts; '
        "the target's own concepts are NOT mastered", () async {
      // Target is the 'middle' root (order 2000). 'early' is mastered;
      // 'middle' (the target) and 'late' are not.
      final early = makeGoal(
        'early',
        order: 1000,
        knownConcepts: ['variables', 'types'],
      );
      final middle = makeGoal(
        'middle',
        order: 2000,
        knownConcepts: ['loops'], // must not appear as mastered
      );
      final late_ = makeGoal(
        'late',
        order: 3000,
        knownConcepts: ['classes'],
      );

      selectedRoot.value = middle;
      selectedChild.value = makeGoal('child', title: 'sub');

      when(() => goals.getRootGoalsOnce())
          .thenAnswer((_) async => [early, middle, late_]);

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'socraticQuestion',
            sections: {'t': '<{known concepts}>'},
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, '<variables\ntypes>\n');
      expect(out, isNot(contains('loops')));
      expect(out, isNot(contains('classes')));
    });

    test('preferredRootGoal is used as the target for the mastered-concepts '
        'cutoff', () async {
      final a = makeGoal('a', order: 1000, knownConcepts: ['c-a']);
      final b = makeGoal('b', order: 2000, knownConcepts: ['c-b']);
      final c = makeGoal('c', order: 3000, knownConcepts: ['c-c']);

      // selectedRoot is 'c' (which would normally master a+b), but
      // preferred is 'b' — so only 'a' should be mastered.
      selectedRoot.value = c;
      selectedChild.value = makeGoal('child');
      preferredRoot.value = b;

      when(() => goals.getRootGoalsOnce())
          .thenAnswer((_) async => [a, b, c]);

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'socraticQuestion',
            sections: {'t': '<{known concepts}>'},
          ),
        ],
      );

      final out = await InstructionGenerator()
          .generateInstructions(ChatRequestType.socraticQuestion);
      expect(out, '<c-a>\n');
    });
  });
}
