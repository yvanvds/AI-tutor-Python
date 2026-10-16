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

  group('content question (#132)', () {
    Future<String> generate(
      List<Instruction> docs, {
      Goal? override,
      Goal? goal,
    }) => InstructionGenerator().generateInstructions(
      ChatRequestType.contentQuestion,
      goalSelection: GoalSelectionState(
        selectedRoot: root(),
        selectedChild: subgoal(),
      ),
      cachedInstructions: docs,
      fetchInstructions: () async => const [],
      fetchRootGoals: () async => const [],
      languageCode: 'nl',
      subgoalOverride: override,
      goalOverride: goal,
    );

    test('a teacher-authored contentQuestion doc is the body, with its tags '
        'filled in', () async {
      final out = await generate([
        makeInstruction('alwaysInclude', {'main': 'always {goal}'}),
        makeInstruction('contentQuestion', {
          'main': 'Answer about the page of {subgoal}; tips: {teachingTips}',
        }),
        makeInstruction('studentQuestion', {'main': 'the other doc'}),
      ]);
      expect(out, contains('always Iteration'));
      expect(out, contains('Answer about the page of Loops; tips: Tip A'));
      expect(out, isNot(contains('the other doc')));
      expect(out, isNot(contains(defaultContentQuestionInstruction)));
      expect(out, isNot(contains('CONTENT QUESTION')));
    });

    test('without one the prompt still assembles, around the built-in body '
        'with its tags filled in', () async {
      final out = await generate([
        makeInstruction('alwaysInclude', {'main': 'always {goal}'}),
        makeInstruction('studentQuestion', {'main': 'the other doc'}),
      ]);
      expect(out, contains('RESPONSE FORMAT — STRICT.'));
      expect(out, contains('always Iteration'));
      expect(out, contains('### CONTENT QUESTION'));
      expect(
        out,
        contains('belongs to the subgoal "Loops" of the goal "Iteration"'),
      );
      expect(out, contains('Do not start an exercise, do not grade'));
      expect(out, contains('{"type": "answer"}'));
      expect(out, isNot(contains('the other doc')));
      expect(out, isNot(contains('{subgoal}')));
      // The language directive still comes last.
      expect(
        out.indexOf('OUTPUT LANGUAGE'),
        greaterThan(out.indexOf('### CONTENT QUESTION')),
      );
    });

    test('with no docs at all the built-in body is the whole middle', () async {
      final out = await generate(const []);
      expect(out, contains('### CONTENT QUESTION'));
      expect(out, contains('Write all student-facing text in Dutch'));
    });

    test('the page of an older subgoal: the override names it, in the '
        'built-in body as in a teacher doc', () async {
      final older = Goal(
        id: 'sub-0',
        title: 'Print',
        parentId: 'root-1',
        order: 0,
        teachingTips: const ['Tip P'],
      );
      final builtIn = await generate(const [], override: older);
      expect(builtIn, contains('belongs to the subgoal "Print"'));
      expect(builtIn, isNot(contains('Loops')));

      final authored = await generate([
        makeInstruction('contentQuestion', {
          'main': 'page of {subgoal}; tips: {teachingTips}',
        }),
      ], override: older);
      expect(authored, contains('page of Print; tips: Tip P'));
      expect(authored, isNot(contains('Loops')));
    });

    // #272: the theory view pages back into earlier goals, so the page can
    // belong to another goal than the active one.
    test('the page of an earlier goal: {goal} is that goal, in the built-in '
        'body and in the always-include section', () async {
      final basics = Goal(id: 'root-0', title: 'Basics', order: -1000);
      final print = Goal(
        id: 'sub-0',
        title: 'Print',
        parentId: 'root-0',
        order: 0,
        teachingTips: const ['Tip P'],
      );
      final out = await generate(
        [
          makeInstruction('alwaysInclude', {
            'main': 'always: {goal} / {subgoal}',
          }),
        ],
        override: print,
        goal: basics,
      );
      expect(
        out,
        contains('belongs to the subgoal "Print" of the goal "Basics"'),
      );
      expect(out, contains('always: Basics / Print'));
      expect(out, isNot(contains('Iteration')));
      expect(out, isNot(contains('Loops')));
    });

    test('no other request type picks up a built-in body', () async {
      final out = await InstructionGenerator().generateInstructions(
        ChatRequestType.studentQuestion,
        goalSelection: GoalSelectionState(
          selectedRoot: root(),
          selectedChild: subgoal(),
        ),
        cachedInstructions: const [],
        fetchInstructions: () async => const [],
        fetchRootGoals: () async => const [],
        languageCode: 'nl',
      );
      expect(out, isNot(contains('CONTENT QUESTION')));
      expect(builtInInstructions.keys, ['contentQuestion']);
    });
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

  group('answer-key directive (#197)', () {
    Future<String> generate(ChatRequestType type) =>
        InstructionGenerator().generateInstructions(
          type,
          goalSelection: GoalSelectionState(
            selectedRoot: root(),
            selectedChild: subgoal(),
          ),
          cachedInstructions: [
            // A teacher's own grading rules, which the directive does not
            // replace.
            makeInstruction('mcqAnswer', {'main': 'Leg kort uit waarom.'}),
            makeInstruction('mcQuestion', {'main': 'Geef vier opties.'}),
          ],
          fetchInstructions: () async => const [],
          fetchRootGoals: () async => const [],
          languageCode: 'nl',
        );

    test(
      'the grader of a multiple-choice pick is told how to treat the key, '
      'after the teacher\'s body and before the language directive',
      () async {
        final out = await generate(ChatRequestType.mcqAnswer);
        expect(out, contains(answerKeyDirective));
        expect(out, contains('Leg kort uit waarom.'));
        final at = out.indexOf('ANSWER KEY — STRICT.');
        expect(at, greaterThan(out.indexOf('Leg kort uit waarom.')));
        expect(at, lessThan(out.indexOf('OUTPUT LANGUAGE')));
      },
    );

    test('it takes the key as the intended answer, yet keeps the grade the '
        'grader\'s own and the key away from the student', () {
      expect(answerKeyDirective, contains('`correct_option`'));
      expect(answerKeyDirective, contains('Take it as the intended answer'));
      expect(
        answerKeyDirective,
        contains('grade the pick by what is actually right, not by the key'),
      );
      expect(
        answerKeyDirective,
        contains('never adjust it to agree with the key'),
      );
      expect(answerKeyDirective, contains('Never mention `correct_option`'));
    });

    test('a wrong key is also said outright, whatever the pick, and never '
        'to the student (#198)', () {
      expect(
        answerKeyDirective,
        contains(
          'When you find the key wrong, add `"keyDisputed": true` to META, '
          'whichever option was picked',
        ),
      );
      expect(
        answerKeyDirective,
        contains('Leave `keyDisputed` out when the key is right'),
      );
      expect(
        answerKeyDirective,
        contains('Never mention `correct_option`, `keyDisputed`'),
      );
      expect(answerKeyDirective, contains('not even that the key is wrong'));
      expect(
        answerKeyDirective,
        contains('on its own merits, without `keyDisputed`'),
      );
    });

    test('no other request type gets it', () async {
      for (final type in [
        ChatRequestType.mcQuestion,
        ChatRequestType.submitCode,
        ChatRequestType.followUpAnswer,
        ChatRequestType.contentQuestion,
        ChatRequestType.status,
      ]) {
        expect(
          await generate(type),
          isNot(contains('ANSWER KEY')),
          reason: type.name,
        );
      }
    });
  });

  // #271 — the chat stays open while a quiz is open: a question, a question
  // about the page or a hint asked then must not give the quiz's answer
  // away, whatever the teacher's docs say.
  group('open-quiz directive (#271)', () {
    Future<String> generate(ChatRequestType type, {required bool quizOpen}) =>
        InstructionGenerator().generateInstructions(
          type,
          goalSelection: GoalSelectionState(
            selectedRoot: root(),
            selectedChild: subgoal(),
          ),
          cachedInstructions: [
            makeInstruction('studentQuestion', {'main': 'Antwoord kort.'}),
            makeInstruction('mcqAnswer', {'main': 'Leg kort uit waarom.'}),
          ],
          fetchInstructions: () async => const [],
          fetchRootGoals: () async => const [],
          languageCode: 'nl',
          quizOpen: quizOpen,
        );

    test(
      'a question next to an open quiz is told not to give its answer '
      'away, after the teacher\'s body and before the language directive',
      () async {
        final out = await generate(
          ChatRequestType.studentQuestion,
          quizOpen: true,
        );
        expect(out, contains(openQuizDirective));
        final at = out.indexOf('OPEN QUIZ — STRICT.');
        expect(at, greaterThan(out.indexOf('Antwoord kort.')));
        expect(at, lessThan(out.indexOf('OUTPUT LANGUAGE')));
      },
    );

    test('so are a question about the page and a hint; no turn without an '
        'open quiz is', () async {
      for (final type in openQuizGuardedTypes) {
        expect(
          await generate(type, quizOpen: true),
          contains('OPEN QUIZ'),
          reason: type.name,
        );
        expect(
          await generate(type, quizOpen: false),
          isNot(contains('OPEN QUIZ')),
          reason: type.name,
        );
      }
      expect(openQuizGuardedTypes, {
        ChatRequestType.studentQuestion,
        ChatRequestType.contentQuestion,
        ChatRequestType.requestHint,
      });
    });

    test('a grading call never gets it, not even with the quiz open: the '
        'pick\'s own, or a follow-up answer after it', () async {
      for (final type in [
        ChatRequestType.mcqAnswer,
        ChatRequestType.followUpAnswer,
        ChatRequestType.submitCode,
        ChatRequestType.socraticFeedback,
        ChatRequestType.explainAnswer,
        ChatRequestType.mcQuestion,
        ChatRequestType.status,
      ]) {
        expect(
          await generate(type, quizOpen: true),
          isNot(contains('OPEN QUIZ')),
          reason: type.name,
        );
      }
    });

    test('a message is no answer and the answer is not given away, not even '
        'after the pick; the key is never mentioned', () {
      expect(openQuizDirective, contains('`open_quiz`'));
      expect(openQuizDirective, contains('`picked`'));
      expect(
        openQuizDirective,
        contains('This message is not an answer to the quiz'),
      );
      expect(
        openQuizDirective,
        contains('tell the student to pick their answer in the quiz'),
      );
      expect(
        openQuizDirective,
        contains('do not say or hint which option is right'),
      );
      expect(openQuizDirective, contains('Once they have picked'));
      expect(
        openQuizDirective,
        contains('Never mention an answer key, `correct_option`'),
      );
    });
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
