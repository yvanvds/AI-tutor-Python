// 1B.1 — Tests `InstructionGenerator.generateInstructions`. The generator
// now takes all its dependencies as named parameters instead of reading from
// a locator. We pass a GoalSelectionState built from ValueNotifiers plus
// direct callbacks to the mocked services.
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
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

/// Strip the constant envelope-contract prefix that every system prompt now
/// starts with. Tests focus on the teacher-edited part of the rendering, not
/// the hard-coded transport contract.
String _withoutEnvelope(String full) {
  if (!full.startsWith(envelopeContract)) return full;
  return full.substring(envelopeContract.length + 1); // +1 for the trailing \n
}

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

    when(() => goals.getRootGoalsOnce()).thenAnswer((_) async => <Goal>[]);
    when(() => instructions.getAll())
        .thenAnswer((_) async => <Instruction>[]);
  });

  tearDown(() {
    selectedRoot.dispose();
    selectedChild.dispose();
    preferredRoot.dispose();
    preferredChild.dispose();
  });

  /// Helper that builds a GoalSelectionState from the current ValueNotifier
  /// values and delegates to InstructionGenerator.
  Future<String> gen(ChatRequestType type) =>
      InstructionGenerator().generateInstructions(
        type,
        goalSelection: GoalSelectionState(
          selectedRoot: selectedRoot.value,
          selectedChild: selectedChild.value,
          preferredRoot: preferredRoot.value,
          preferredChild: preferredChild.value,
          cachedRoots: const [],
        ),
        cachedInstructions: const [],
        fetchInstructions: instructions.getAll,
        fetchRootGoals: goals.getRootGoalsOnce,
      );

  group('generateInstructions — guard clauses', () {
    test('no selected root goal → empty string', () async {
      selectedChild.value = makeGoal('child');
      final out = await gen(ChatRequestType.socraticQuestion);
      expect(out, '');
      verifyNever(() => instructions.getAll());
    });

    test('no selected child goal → empty string', () async {
      selectedRoot.value = makeGoal('root');
      final out = await gen(ChatRequestType.socraticQuestion);
      expect(out, '');
      verifyNever(() => instructions.getAll());
    });
  });

  group('generateInstructions — envelope contract', () {
    test('every non-empty rendering starts with the envelope contract',
        () async {
      selectedRoot.value = makeGoal('root');
      selectedChild.value = makeGoal('child');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(
            id: 'alwaysInclude',
            sections: {'a': 'X'},
          ),
        ],
      );

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(out, startsWith(envelopeContract));
    });
  });

  group('generateInstructions — section selection & ordering', () {
    test('alwaysInclude renders before per-type sections (cache-friendly '
        'ordering)', () async {
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

      final out = await gen(ChatRequestType.socraticQuestion);
      final body = _withoutEnvelope(out);

      // alwaysInclude first, then per-type sections in map iteration order.
      expect(body, 'ALWAYS-RULES\nTYPE-INTRO\nTYPE-BODY\n');
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

      final out = await gen(ChatRequestType.requestHint);
      expect(_withoutEnvelope(out), 'ALWAYS\n');
    });

    test('no matching id at all → only the envelope contract is emitted',
        () async {
      selectedRoot.value = makeGoal('root');
      selectedChild.value = makeGoal('child');

      when(() => instructions.getAll()).thenAnswer(
        (_) async => [
          Instruction(id: 'somethingElse', sections: {'x': 'X'}),
        ],
      );

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(_withoutEnvelope(out), '');
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

      final out = await gen(ChatRequestType.socraticQuestion);
      // No mastered concepts because the only root goal IS the target —
      // the loop short-circuits before adding anything.
      expect(
        _withoutEnvelope(out),
        'goal=Lussen sub=For-loop sug=s1\ns2 known=\n',
      );
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

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(
        _withoutEnvelope(out),
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

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(_withoutEnvelope(out), 'goal=PREF-ROOT sub=PREF-CHILD\n');
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

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(_withoutEnvelope(out), '<variables\ntypes>\n');
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

      final out = await gen(ChatRequestType.socraticQuestion);
      expect(_withoutEnvelope(out), '<c-a>\n');
    });
  });
}
