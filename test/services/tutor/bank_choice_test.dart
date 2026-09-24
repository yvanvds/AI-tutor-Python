// Issue #186 — which question, if any, the conductor takes from the
// question bank for a plan (CONDUCTOR_POLICY §2.7): what fits, what may be
// served, what is new to the student, the minimum, the mix, and the order.

import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/bank_choice.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

const _lo = LearningObjective(
  id: 'lo-print',
  statement: 'print a sum',
  kind: LoKind.predict,
);

const _reason = TurnSelectionReason(
  candidateLOs: [],
  chosenReason: 'test',
  notchDropFired: false,
);

final _earlier = Goal(id: 's0', title: 'Print', parentId: 'r1', order: 500);

QuestionPlan _plan({
  ChatRequestType type = ChatRequestType.mcQuestion,
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
  WarmUpReview? warmUp,
  Recheck? recheck,
  List<LearningObjective> targetLOs = const [_lo],
}) => QuestionPlan(
  type: type,
  difficulty: difficulty,
  targetLOs: targetLOs,
  reason: _reason,
  warmUp: warmUp,
  recheck: recheck,
);

/// A bank multiple-choice question on `s1` / `lo-print` / medium / `en`,
/// the key `2`, created by another student.
BankQuestion _mcq(
  String id, {
  String subgoalId = 's1',
  List<String> targetLOIds = const ['lo-print'],
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
  String language = 'en',
  String createdByUid = 'other',
  BankQuestionStatus status = BankQuestionStatus.active,
  String? correct = '2',
  List<String> options = const ['2', '11', 'Error'],
  List<BankOptionFeedback> optionFeedback = const [],
  DateTime? lastAskedAt,
  int askedCount = 1,
}) => BankQuestion(
  id: id,
  subgoalId: subgoalId,
  rootGoalId: 'r1',
  targetLOIds: targetLOIds,
  questionType: ChatRequestType.mcQuestion,
  difficulty: difficulty,
  language: language,
  payload: {
    'type': 'multiple_choice',
    'prompt': 'Wat drukt print(1 + 1) af? ($id)',
    'code': 'print(1 + 1)',
    'options': [
      for (final o in options) {'option': o},
    ],
    'correct': ?correct,
  },
  model: 'gpt-5-mini',
  createdAt: DateTime.utc(2026, 9, 20),
  createdByUid: createdByUid,
  askedCount: askedCount,
  lastAskedAt: lastAskedAt,
  optionFeedback: optionFeedback,
  status: status,
);

BankQuestion _completeCode(String id, {Map<String, dynamic>? payload}) =>
    BankQuestion(
      id: id,
      subgoalId: 's1',
      rootGoalId: 'r1',
      targetLOIds: const ['lo-print'],
      questionType: ChatRequestType.completeCodeQuestion,
      difficulty: QuestionDifficulty.medium,
      language: 'en',
      payload:
          payload ??
          {
            'type': 'complete_code',
            'prompt': 'Toon een groet ($id).',
            'code': 'print(___)',
          },
      model: 'gpt-5-mini',
      createdAt: DateTime.utc(2026, 9, 20),
      createdByUid: 'other',
    );

/// A `Random` whose rolls are scripted.
class _Rolls implements Random {
  _Rolls(this.values);
  final List<double> values;
  int calls = 0;

  @override
  double nextDouble() => values[calls++];

  @override
  int nextInt(int max) => throw UnimplementedError();

  @override
  bool nextBool() => throw UnimplementedError();
}

BankPick _pick(
  Iterable<BankQuestion> bank, {
  QuestionPlan? plan,
  Set<String> alreadyAsked = const {},
  int minimum = 1,
  String language = 'en',
}) => BankChoice.pick(
  plan: plan ?? _plan(),
  subgoalId: (plan ?? _plan()).offSubgoal?.id ?? 's1',
  bank: bank,
  alreadyAsked: alreadyAsked,
  uid: 'me',
  language: language,
  minimum: minimum,
);

void main() {
  group('BankMix', () {
    test('defaults to N = 8 and p = 0.5', () {
      const mix = BankMix();
      expect(mix.minimum, 8);
      expect(mix.share, 0.5);
      expect(PolicyConstants.bankMinimum, 8);
      expect(PolicyConstants.bankShare, 0.5);
    });

    test('config/global overrides each knob on its own', () {
      final both = BankMix.fromConfig(
        const GlobalConfig(
          model: 'm',
          apiKey: '',
          questionBankMinimum: 3,
          questionBankShare: 0.25,
        ),
      );
      expect((both.minimum, both.share), (3, 0.25));

      final onlyShare = BankMix.fromConfig(
        const GlobalConfig(model: 'm', apiKey: '', questionBankShare: 1),
      );
      expect((onlyShare.minimum, onlyShare.share), (8, 1.0));

      final none = BankMix.fromConfig(null);
      expect((none.minimum, none.share), (8, 0.5));
    });
  });

  group('which plans the bank may serve', () {
    test('multiple choice and the three code types; not socratic', () {
      const mix = BankMix();
      for (final type in [
        ChatRequestType.mcQuestion,
        ChatRequestType.completeCodeQuestion,
        ChatRequestType.explainCodeQuestion,
        ChatRequestType.writeCodeQuestion,
      ]) {
        expect(BankChoice.mayServe(_plan(type: type), mix), isTrue);
      }
      expect(
        BankChoice.mayServe(_plan(type: ChatRequestType.socraticQuestion), mix),
        isFalse,
      );
      expect(BankChoice.mayServe(_plan(targetLOs: const []), mix), isFalse);
    });

    test('a share of 0 switches it off, warm-up and recheck included', () {
      const off = BankMix(share: 0);
      expect(BankChoice.mayServe(_plan(), off), isFalse);
      final warmUp = _plan(warmUp: WarmUpReview(subgoal: _earlier));
      expect(BankChoice.rollsForBank(warmUp, off, _Rolls(const [])), isFalse);
    });

    test('an ordinary plan rolls against p; a warm-up or recheck never '
        'rolls', () {
      const mix = BankMix(share: 0.5);
      expect(BankChoice.rollsForBank(_plan(), mix, _Rolls([0.49])), isTrue);
      expect(BankChoice.rollsForBank(_plan(), mix, _Rolls([0.5])), isFalse);

      final rolls = _Rolls(const []);
      expect(
        BankChoice.rollsForBank(
          _plan(warmUp: WarmUpReview(subgoal: _earlier)),
          mix,
          rolls,
        ),
        isTrue,
      );
      expect(
        BankChoice.rollsForBank(
          _plan(
            recheck: Recheck(subgoal: _earlier, rule: RecheckRule.nearGoal),
          ),
          mix,
          rolls,
        ),
        isTrue,
      );
      expect(rolls.calls, 0);
    });

    test('the minimum is N for an ordinary plan and 1 off the subgoal', () {
      const mix = BankMix(minimum: 8);
      expect(BankChoice.minimumFor(_plan(), mix), 8);
      expect(
        BankChoice.minimumFor(
          _plan(warmUp: WarmUpReview(subgoal: _earlier)),
          mix,
        ),
        1,
      );
      expect(
        BankChoice.minimumFor(
          _plan(
            recheck: Recheck(subgoal: _earlier, rule: RecheckRule.unconfirmed),
          ),
          mix,
        ),
        1,
      );
    });
  });

  group('what fits a plan', () {
    test('subgoal, target LO, type, difficulty and language must all match; '
        'a hidden question never fits', () {
      final plan = _plan();
      bool fits(BankQuestion q) =>
          BankChoice.fits(q, plan: plan, subgoalId: 's1', language: 'en');

      expect(fits(_mcq('a')), isTrue);
      expect(fits(_mcq('b', subgoalId: 's2')), isFalse);
      expect(fits(_mcq('c', targetLOIds: const ['lo-other'])), isFalse);
      expect(fits(_mcq('d', difficulty: QuestionDifficulty.hard)), isFalse);
      expect(fits(_mcq('e', language: 'nl')), isFalse);
      expect(fits(_mcq('f', status: BankQuestionStatus.hidden)), isFalse);
      expect(fits(_completeCode('g')), isFalse, reason: 'another type');
    });
  });

  group('what may be served', () {
    test('a multiple-choice question needs a key among its options that the '
        'grader never contradicted', () {
      expect(BankChoice.servable(_mcq('ok')), isTrue);
      expect(BankChoice.servable(_mcq('no-key', correct: null)), isFalse);
      expect(BankChoice.servable(_mcq('bad-key', correct: '3')), isFalse);
      expect(
        BankChoice.servable(
          _mcq(
            'doubted',
            optionFeedback: const [
              BankOptionFeedback(
                option: '11',
                text: 'Juist!',
                quality: AnswerQuality.correct,
              ),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        BankChoice.servable(
          _mcq(
            'agreed',
            optionFeedback: const [
              BankOptionFeedback(
                option: '11',
                text: 'Nee.',
                quality: AnswerQuality.wrong,
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('a code question needs a payload a handler takes', () {
      expect(BankChoice.servable(_completeCode('ok')), isTrue);
      expect(
        BankChoice.servable(
          _completeCode('broken', payload: const {'type': 'nonsense'}),
        ),
        isFalse,
      );
    });
  });

  group('pick', () {
    test('fewer than the minimum new questions: none — the plan is '
        'generated', () {
      final bank = [_mcq('a'), _mcq('b')];
      final pick = _pick(bank, minimum: 3);
      expect(pick.question, isNull);
      expect(pick.eligible, 2);
      expect(_pick(bank, minimum: 2).question, isNotNull);
    });

    test('a question the student answered, saw this session, or got first '
        'is not new and does not count', () {
      final bank = [
        _mcq('answered'),
        _mcq('mine', createdByUid: 'me'),
        _mcq('new'),
      ];
      final pick = _pick(bank, alreadyAsked: {'answered'}, minimum: 1);
      expect(pick.question?.id, 'new');
      expect(pick.eligible, 1);
      expect(_pick(bank, alreadyAsked: {'answered', 'new'}).question, isNull);
    });

    test('the least recently asked goes first, then the least asked, then '
        'the id', () {
      final bank = [
        _mcq('recent', lastAskedAt: DateTime.utc(2026, 9, 24, 10)),
        _mcq('old', lastAskedAt: DateTime.utc(2026, 9, 20)),
        _mcq('older-b', lastAskedAt: DateTime.utc(2026, 9, 19), askedCount: 5),
        _mcq('older-a', lastAskedAt: DateTime.utc(2026, 9, 19), askedCount: 5),
        _mcq('older-few', lastAskedAt: DateTime.utc(2026, 9, 19)),
      ];
      expect(_pick(bank).question?.id, 'older-few');
      expect(_pick(bank, alreadyAsked: {'older-few'}).question?.id, 'older-a');
      expect(
        _pick(bank, alreadyAsked: {'older-few', 'older-a'}).question?.id,
        'older-b',
      );
    });

    test('a warm-up review takes the older subgoal\'s questions', () {
      final plan = _plan(warmUp: WarmUpReview(subgoal: _earlier));
      final bank = [_mcq('s0-q', subgoalId: 's0'), _mcq('s1-q')];
      expect(_pick(bank, plan: plan).question?.id, 's0-q');
    });
  });
}
