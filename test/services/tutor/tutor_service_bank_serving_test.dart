// Issue #186 — the tutor serves questions from the question bank once it
// holds enough, mixed with fresh generation, and grades a multiple-choice
// pick on a bank question from its answer key. And #197: the grading call of
// a pick — on a bank question or a fresh one — is told that key, and a
// grader told it can still overrule it.
//
// The real `TutorService` and the real `QuestionBankService` over a filled
// in-memory `questions` container; the connector replays canned chunks and
// records what each call carried, the conductor is mocked (its plans and
// what it is handed to integrate), the turn history records what it gets
// and answers which questions the student already answered, and the dice
// are pinned.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';
import '../../helpers/unprovisioned_cosmos.dart';

/// Replays one canned chunk list per streamed request and keeps what each
/// request carried: its input, its history scope and the history itself.
class _Connector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  final List<({String input, PreviousInputs scope})> sent = [];
  final List<List<Map<String, String>>> histories = [];

  Stream<StreamChunk> _next() {
    if (scripts.isEmpty) {
      return Stream.value(
        StreamFailed(
          StateError('script exhausted'),
          StackTrace.current,
          ChatNotice.raw('script exhausted'),
        ),
      );
    }
    return Stream.fromIterable(scripts.removeAt(0));
  }

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    sent.add((input: input, scope: inputs));
    histories.add(historyForCall(inputs));
    return _next();
  }

  @override
  Stream<StreamChunk> resendRequestStream() => _next();
}

class _Generator extends InstructionGenerator {
  @override
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
    required String languageCode,
    List<LearningObjective> targetLOs = const [],
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
    Goal? subgoalOverride,
  }) async => 'system prompt';
}

class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

class _SignedIn extends AuthService {
  @override
  AccountIdentity? build() => const AccountIdentity(
    oid: 'u1',
    displayName: 'Sam Student',
    email: 'sam@example.com',
    firstName: 'Sam',
    lastName: 'Student',
    isTeacher: false,
  );
}

/// The school's `config/global`, as the app has it in memory.
class _Config extends GlobalConfigService {
  _Config(this.config);
  final GlobalConfig config;

  @override
  GlobalConfig? build() => config;
}

/// Records every turn record; answers which bank questions the student
/// already answered, or fails to.
class _History extends TurnHistoryService {
  _History() : super(getUid: () => 'u1');

  final List<PersistedTurnRecord> records = [];
  Set<String> answered = {};
  Object? readError;
  final List<String> reads = [];

  @override
  Future<void> append(PersistedTurnRecord record) async => records.add(record);

  @override
  Future<Set<String>> listQuestionIdsFor(String subgoalId) async {
    reads.add(subgoalId);
    final error = readError;
    if (error != null) throw error;
    return answered;
  }
}

/// A `Random` whose rolls are scripted; a roll nobody scripted fails the
/// test instead of being swallowed as a failed bank read.
class _Rolls implements Random {
  _Rolls([this.values = const []]);
  final List<double> values;
  int calls = 0;

  @override
  double nextDouble() {
    if (calls >= values.length) fail('an unexpected roll of the dice');
    return values[calls++];
  }

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// A container that counts the queries it is sent before passing them on.
class _CountingContainer implements CosmosContainer {
  _CountingContainer(this.inner);
  final CosmosContainer inner;
  int queries = 0;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) {
    queries++;
    return inner.query(
      sql,
      parameters: parameters,
      partitionKey: partitionKey,
      crossPartition: crossPartition,
    );
  }

  // upsert, delete and executeBatch: the bank reads and replaces only.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) => inner.read(id, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => inner.create(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => inner.replace(id, doc, partitionKey: partitionKey);
}

/// A `questions` container whose queries never answer.
class _SilentContainer extends MockCosmosContainer {
  _SilentContainer() {
    when(
      () => query(
        any(),
        parameters: any(named: 'parameters'),
        partitionKey: any(named: 'partitionKey'),
        crossPartition: any(named: 'crossPartition'),
      ),
    ).thenAnswer((_) => Completer<List<Map<String, dynamic>>>().future);
    when(() => read(any(), partitionKey: any(named: 'partitionKey')))
        .thenAnswer((_) => Completer<Map<String, dynamic>?>().future);
  }
}

const _lo = LearningObjective(
  id: 'lo-print',
  statement: 'predict what print shows',
  kind: LoKind.predict,
);

const _reason = TurnSelectionReason(
  candidateLOs: [],
  chosenReason: 'test',
  notchDropFired: false,
);

TurnOutcome _outcome(AnswerQuality quality) => TurnOutcome(
  overallQuality: quality,
  subgoalAdvanced: false,
  degraded: false,
  loSignals: const [],
  appliedSignals: const [],
  loStatusAfter: const [],
  subgoalProgressAfter: 0.2,
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  hadFallback: false,
);

QuestionPlan _plan(
  ChatRequestType type, {
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
  WarmUpReview? warmUp,
}) => QuestionPlan(
  type: type,
  difficulty: difficulty,
  targetLOs: const [_lo],
  reason: _reason,
  warmUp: warmUp,
);

List<StreamChunk> _reply(ChatResponse response) => [
  const StreamTextDelta('…'),
  StreamCompleted(response),
];

const _key = '2';
const _wrong = '11';
const _wrongText = 'Nee: 1 + 1 is een som, geen tekst.';
const _rightText = 'Juist: print toont de som.';

/// A bank multiple-choice question on `s1` / `lo-print` / medium / `en`,
/// created by another student, the key `2`.
Map<String, dynamic> _mcqDoc(
  String tag, {
  String subgoalId = 's1',
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
  String createdByUid = 'someone-else',
  DateTime? lastAskedAt,
  List<BankOptionFeedback> feedback = const [],
  String status = 'active',
}) {
  final q = BankQuestion.fromResponse(
    MultipleChoice(
      type: 'multiple_choice',
      prompt: 'Wat drukt dit af? ($tag)',
      code: 'print(1 + 1)  # $tag',
      options: const [_key, _wrong, 'Error'],
      correct: _key,
    ),
    subgoalId: subgoalId,
    rootGoalId: 'r1',
    targetLOIds: const ['lo-print'],
    difficulty: difficulty,
    language: 'en',
    model: 'gpt-5-mini',
    createdByUid: createdByUid,
    createdAt: DateTime.utc(2026, 9, 20),
  )!;
  return {
    ...q.toMap(),
    'askedCount': 1,
    'lastAskedAt': (lastAskedAt ?? DateTime.utc(2026, 9, 21)).toIso8601String(),
    'optionFeedback': [for (final f in feedback) f.toJson()],
    'status': status,
  };
}

const _feedbackOnWrong = BankOptionFeedback(
  option: _wrong,
  text: _wrongText,
  quality: AnswerQuality.wrong,
);
const _feedbackOnKey = BankOptionFeedback(
  option: _key,
  text: _rightText,
  quality: AnswerQuality.correct,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late _History history;
  late InMemoryCosmos store;
  late ChatService chat;
  ProviderContainer? pc;
  final graded = <GradedAnswer>[];

  final root = Goal(id: 'r1', title: 'Basics', order: 0);
  final earlier = Goal(
    id: 's0',
    title: 'Print',
    parentId: 'r1',
    order: 500,
    objectives: const [_lo],
  );
  final active = Goal(
    id: 's1',
    title: 'Sums',
    parentId: 'r1',
    order: 1000,
    objectives: const [_lo],
  );

  setUpAll(() {
    registerFallbackValue(QuestionPlan.noResult);
    registerFallbackValue(
      const GradedAnswer(
        overallQuality: AnswerQuality.wrong,
        signals: [],
        hadFallback: true,
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connector = _Connector();
    history = _History();
    store = InMemoryCosmos();
    chat = ChatService();
    graded.clear();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((inv) async {
      final answer = inv.namedArguments[#answer] as GradedAnswer;
      graded.add(answer);
      return _outcome(answer.overallQuality);
    });
  });

  tearDown(() {
    pc?.dispose();
    pc = null;
    chat.dispose();
  });

  /// Boots the tutor over the bank [docs] (or [bank]), with the school's
  /// mix at N = [minimum] and p = [share] (the defaults when null), and the
  /// dice pinned to [rolls].
  Future<QuestionBankService> boot({
    List<Map<String, dynamic>> docs = const [],
    QuestionBankService? bank,
    int? minimum,
    double? share,
    Random? rolls,
  }) async {
    for (final d in docs) {
      store.upsert(d);
    }
    final service = bank ?? QuestionBankService(container: store.container);
    final goals = MockGoalsService();
    when(() => goals.streamChildren(any())).thenAnswer((_) => Stream.empty());
    when(() => goals.getChildrenOnce(any()))
        .thenAnswer((_) async => [earlier, active]);
    final sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});

    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(
          () => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: _Generator(),
            random: rolls ?? _Rolls(),
          ),
        ),
        authServiceProvider.overrideWith(_SignedIn.new),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(goals),
        goalSelectionProvider.overrideWith(
          () => _PresetSelection(root, active),
        ),
        soundServiceProvider.overrideWithValue(sound),
        turnHistoryServiceProvider.overrideWithValue(history),
        questionBankServiceProvider.overrideWithValue(service),
        globalConfigServiceProvider.overrideWith(
          () => _Config(
            GlobalConfig(
              model: 'gpt-5-mini',
              apiKey: '',
              questionBankMinimum: minimum,
              questionBankShare: share,
            ),
          ),
        ),
      ],
    );
    // The app keeps the config alive (the update gate watches it).
    pc!.read(globalConfigServiceProvider);
    pc!.read(modeProvider.notifier).state = SessionMode.practice;
    pc!.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    return service;
  }

  TutorService tutor() => pc!.read(tutorServiceProvider.notifier);

  void planNext(QuestionPlan plan) =>
      when(() => conductor.planNext()).thenAnswer((_) async => plan);

  BankQuestion stored(String id) => BankQuestion.tryFromCosmos(store[id]!)!;

  String idOf(Map<String, dynamic> doc) => doc['id'] as String;

  List<String> tutorTexts() => chat.controller.messages
      .whereType<TextMessage>()
      .map((m) => m.text)
      .toList();

  group('a multiple-choice question from the bank', () {
    test('once the bank holds N new fitting questions and the roll says '
        'bank, the least recently asked one is served: no call, its options '
        'shuffled, the ask counted, its exercise opened on it', () async {
      final older = _mcqDoc('older', lastAskedAt: DateTime.utc(2026, 9, 19));
      final newer = _mcqDoc('newer', lastAskedAt: DateTime.utc(2026, 9, 22));
      final bank = await boot(
        docs: [older, newer],
        minimum: 2,
        share: 0.5,
        rolls: _Rolls([0.2]),
      );
      final plan = _plan(ChatRequestType.mcQuestion);
      planNext(plan);

      await tutor().requestExercise();
      await bank.idle;

      expect(connector.sent, isEmpty, reason: 'no generation call');
      final mcq = pc!.read(activeMcqProvider)!;
      expect(mcq.prompt, 'Wat drukt dit af? (older)');
      expect(mcq.options.toSet(), {_key, _wrong, 'Error'});
      expect(tutor().state, TutorState.idle);
      verify(() => conductor.notePlannedQuestion(plan)).called(1);

      final q = stored(idOf(older));
      expect(q.askedCount, 2);
      expect(q.lastAskedAt!.isAfter(DateTime.utc(2026, 9, 23)), isTrue);
      expect(stored(idOf(newer)).askedCount, 1);

      // The exercise starts with the question, for a grading call to read.
      expect(connector.exerciseHistory, hasLength(1));
      final first = jsonDecode(connector.exerciseHistory.single['content']!);
      expect(first['type'], 'multiple_choice');
      expect(first['prompt'], 'Wat drukt dit af? (older)');
      expect(
        first.containsKey('correct'),
        isFalse,
        reason: 'the key goes only to the grading call of a pick (#197)',
      );
      expect(history.reads, ['s1']);
    });

    test('a pick whose feedback the bank holds is graded from the key with '
        'no call: the stored text in its colour, a fixed moderate negative '
        'on the target LO at the plan\'s level, and a turn record that names '
        'the question', () async {
      final doc = _mcqDoc('q', feedback: const [_feedbackOnWrong]);
      final bank = await boot(docs: [doc], minimum: 1, share: 1);
      final plan = _plan(ChatRequestType.mcQuestion);
      planNext(plan);
      await tutor().requestExercise();

      await tutor().submitMcqAnswer(_wrong);
      await bank.idle;

      expect(connector.sent, isEmpty, reason: 'no call at all');
      final mcq = pc!.read(activeMcqProvider)!;
      expect(mcq.feedback, _wrongText);
      expect(mcq.feedbackQuality, AnswerQuality.wrong);
      expect(tutor().state, TutorState.idle);

      final answer = graded.single;
      expect(answer.overallQuality, AnswerQuality.wrong);
      expect(answer.fromAnswerKey, isTrue);
      expect(answer.hadFallback, isFalse);
      expect(answer.isFollowUp, isFalse);
      expect(answer.signals, hasLength(1));
      final signal = answer.signals.single;
      expect(signal.subgoalId, 's1');
      expect(signal.loId, 'lo-print');
      expect(signal.kind, LoSignalKind.negative);
      expect(signal.strength, LoSignalStrength.moderate);
      verify(
        () => conductor.integrateAnswer(
          plan: plan,
          answer: any(named: 'answer'),
        ),
      ).called(1);

      final record = history.records.single;
      expect(record.questionId, idOf(doc));
      expect(record.fromBank, isTrue);
      expect(record.gradedByKey, isTrue);
      expect(record.difficulty, QuestionDifficulty.medium);
      expect(record.overallQuality, AnswerQuality.wrong);
      expect(record.usage, isNull, reason: 'no call, no tokens');

      final q = stored(idOf(doc));
      expect(q.answeredCount, 1);
      expect(q.correctCount, 0);
      expect(q.optionFeedback, hasLength(1), reason: 'the text was there');

      // The exchange is on the history a later status report reads.
      final last = connector.allHistory.last;
      expect(jsonDecode(last['content']!)['prompt'], _wrongText);
      final exchange = jsonDecode(
        connector.allHistory[connector.allHistory.length - 2]['content']!,
      );
      expect(exchange['answer'], _wrong);
      expect(
        exchange['correct_option'],
        _key,
        reason: 'as the grading call would have carried it (#197)',
      );
    });

    test('the key is a strong positive', () async {
      final doc = _mcqDoc('q', feedback: const [_feedbackOnKey]);
      final bank = await boot(docs: [doc], minimum: 1, share: 1);
      planNext(_plan(ChatRequestType.mcQuestion));
      await tutor().requestExercise();

      await tutor().submitMcqAnswer(_key);
      await bank.idle;

      expect(connector.sent, isEmpty);
      expect(
        pc!.read(activeMcqProvider)!.feedbackQuality,
        AnswerQuality.correct,
      );
      final signal = graded.single.signals.single;
      expect(graded.single.overallQuality, AnswerQuality.correct);
      expect(signal.kind, LoSignalKind.positive);
      expect(signal.strength, LoSignalStrength.strong);
      expect(stored(idOf(doc)).correctCount, 1);
    });

    test('a pick the bank has no feedback for costs one grading call on the '
        'exercise\'s own exchange; the key decides, the text is kept for the '
        'next student, and the grader\'s follow-up is not asked', () async {
      final doc = _mcqDoc('q');
      final bank = await boot(docs: [doc], minimum: 1, share: 1);
      planNext(_plan(ChatRequestType.mcQuestion));
      await tutor().requestExercise();

      connector.scripts.add(
        _reply(
          McqFeedback(
            type: 'mcq_feedback',
            quality: AnswerQuality.partial,
            prompt: _wrongText,
            loSignals: const [
              LoSignal(
                subgoalId: 's1',
                loId: 'lo-print',
                kind: LoSignalKind.negative,
                strength: LoSignalStrength.weak,
              ),
            ],
            followUp: const FollowUp(question: 'En print("1" + "1")?'),
          ),
        ),
      );
      await tutor().submitMcqAnswer(_wrong);
      await bank.idle;

      expect(connector.sent, hasLength(1));
      expect(connector.sent.single.scope, PreviousInputs.exercise);
      expect(
        jsonDecode(connector.histories.single.first['content']!)['prompt'],
        'Wat drukt dit af? (q)',
        reason: 'the grader reads the bank question as the exercise\'s own',
      );
      expect(
        jsonDecode(connector.sent.single.input)['correct_option'],
        _key,
        reason: 'the grader is told the key it is checked against (#197)',
      );
      final mcq = pc!.read(activeMcqProvider)!;
      expect(mcq.feedback, _wrongText);
      expect(mcq.feedbackQuality, AnswerQuality.partial, reason: 'its colour');

      final answer = graded.single;
      expect(answer.fromAnswerKey, isTrue);
      expect(answer.overallQuality, AnswerQuality.wrong);
      expect(answer.signals.single.strength, LoSignalStrength.moderate);
      expect(history.records.single.gradedByKey, isTrue);

      expect(tutorTexts(), isNot(contains('En print("1" + "1")?')));
      expect(tutor().state, TutorState.idle);

      final q = stored(idOf(doc));
      expect(q.optionFeedback.single.toJson(), {
        'option': _wrong,
        'text': _wrongText,
        'quality': 'partial',
      });
      expect(q.graderDisagreesWithKey, isFalse);
    });

    test('when the grader contradicts the key, its grade stands as for a '
        'fresh question, and the question is not served again', () async {
      final doc = _mcqDoc('q');
      final bank = await boot(docs: [doc], minimum: 1, share: 1);
      planNext(_plan(ChatRequestType.mcQuestion));
      await tutor().requestExercise();

      connector.scripts.add(
        _reply(
          McqFeedback(
            type: 'mcq_feedback',
            quality: AnswerQuality.wrong,
            prompt: 'Nee, dat klopt niet.',
            loSignals: const [
              LoSignal(
                subgoalId: 's1',
                loId: 'lo-print',
                kind: LoSignalKind.negative,
                strength: LoSignalStrength.strong,
              ),
            ],
          ),
        ),
      );
      await tutor().submitMcqAnswer(_key);
      await bank.idle;

      // The grader saw the key and still judged the other way (#197): the
      // directive keeps its grade its own, so the contradiction is real.
      expect(jsonDecode(connector.sent.single.input)['correct_option'], _key);
      final answer = graded.single;
      expect(answer.fromAnswerKey, isFalse);
      expect(answer.overallQuality, AnswerQuality.wrong);
      expect(answer.signals.single.strength, LoSignalStrength.strong);
      final record = history.records.single;
      expect(record.fromBank, isTrue);
      expect(record.gradedByKey, isFalse);
      expect(stored(idOf(doc)).graderDisagreesWithKey, isTrue);

      // A new session: the question is new to nobody's eyes but its key is
      // in doubt, so the next plan is generated.
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(2)',
            options: const ['2', 'Error'],
          ),
        ),
      );
      history.answered = {};
      await tutor().advanceFromMcq();
      expect(connector.sent, hasLength(2));
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers');
    });
  });

  // #197: the key reaches the grader of a pick — on a fresh question too —
  // and nothing before it. The bank is switched off (p = 0) so every
  // question here is generated.
  group('the answer key of a fresh question (#197)', () {
    MultipleChoice fresh({String? correct = _key, String prompt = 'Vers'}) =>
        MultipleChoice(
          type: 'multiple_choice',
          prompt: prompt,
          code: 'print(1 + 1)',
          options: const [_key, _wrong, 'Error'],
          correct: correct,
        );

    List<StreamChunk> grade(AnswerQuality quality, String text) => _reply(
      McqFeedback(type: 'mcq_feedback', quality: quality, prompt: text),
    );

    Map<String, dynamic> input(int i) =>
        jsonDecode(connector.sent[i].input) as Map<String, dynamic>;

    test('the grading call of a pick carries it as option text; the question '
        'on the exercise\'s history, which every call on the exercise reads, '
        'does not', () async {
      final bank = await boot(share: 0);
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(fresh()));
      await tutor().requestExercise();

      final question = jsonDecode(connector.exerciseHistory.single['content']!);
      expect(question['prompt'], 'Vers');
      expect(question.containsKey('correct'), isFalse);

      connector.scripts.add(grade(AnswerQuality.wrong, _wrongText));
      await tutor().submitMcqAnswer(_wrong);
      await bank.idle;

      expect(connector.sent, hasLength(2));
      expect(input(0).containsKey('correct_option'), isFalse);
      expect(input(1)['request_type'], 'mcq_answer');
      expect(input(1)['answer'], _wrong);
      expect(input(1)['correct_option'], _key);
      final carried = jsonDecode(connector.histories[1].single['content']!);
      expect(carried.containsKey('correct'), isFalse);

      // A fresh key is unchecked: the grader's grade is the grade.
      expect(graded.single.fromAnswerKey, isFalse);
      expect(history.records.single.gradedByKey, isFalse);
      expect(pc!.read(activeMcqProvider)!.feedback, _wrongText);
    });

    test('text typed while the exercise is a quiz goes to the grader too, but '
        'it is no pick: no key', () async {
      await boot(share: 0);
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(fresh()));
      await tutor().requestExercise();

      connector.scripts.add(grade(AnswerQuality.wrong, 'Kies een optie.'));
      await tutor().handleStudentMessage('Welke is het?');

      expect(input(1)['request_type'], 'mcq_answer');
      expect(input(1)['answer'], 'Welke is het?');
      expect(input(1).containsKey('correct_option'), isFalse);
    });

    test('a question without a key sends none — also after one that had '
        'a key', () async {
      await boot(share: 0);
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(fresh()));
      await tutor().requestExercise();
      connector.scripts.add(grade(AnswerQuality.correct, _rightText));
      await tutor().submitMcqAnswer(_key);
      expect(input(1)['correct_option'], _key);

      connector.scripts.add(_reply(fresh(correct: null, prompt: 'Zonder')));
      await tutor().advanceFromMcq();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Zonder');
      connector.scripts.add(grade(AnswerQuality.correct, _rightText));
      await tutor().submitMcqAnswer(_key);

      expect(connector.sent, hasLength(4));
      expect(input(3)['request_type'], 'mcq_answer');
      expect(input(3).containsKey('correct_option'), isFalse);
    });

    test('a grader that sees the key can still overrule it: its grade stands '
        'and the bank flags the question', () async {
      final bank = await boot(share: 0);
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(fresh()));
      await tutor().requestExercise();

      connector.scripts.add(grade(AnswerQuality.wrong, 'Nee, dat klopt niet.'));
      await tutor().submitMcqAnswer(_key);
      await bank.idle;

      expect(input(1)['correct_option'], _key);
      expect(graded.single.overallQuality, AnswerQuality.wrong);
      final q = BankQuestion.tryFromCosmos(store.docs.values.single)!;
      expect(q.correctOption, _key);
      expect(q.graderDisagreesWithKey, isTrue);
    });
  });

  group('what is new to the student', () {
    test('a question they answered before, one they got first, and one this '
        'session put in front of them are not served again', () async {
      final answered = _mcqDoc('answered');
      final theirs = _mcqDoc('theirs', createdByUid: 'u1');
      final a = _mcqDoc('a', lastAskedAt: DateTime.utc(2026, 9, 18));
      final b = _mcqDoc('b', lastAskedAt: DateTime.utc(2026, 9, 19));
      history.answered = {idOf(answered)};
      final bank = await boot(
        docs: [answered, theirs, a, b],
        minimum: 1,
        share: 1,
      );
      planNext(_plan(ChatRequestType.mcQuestion));

      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Wat drukt dit af? (a)');

      // Left unanswered: the next exercise is the other new one ...
      pc!.read(activeMcqProvider.notifier).state = null;
      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Wat drukt dit af? (b)');

      // ... and then there is none left: generated.
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(3)',
            options: const ['3', 'Error'],
          ),
        ),
      );
      pc!.read(activeMcqProvider.notifier).state = null;
      await tutor().requestExercise();
      await bank.idle;
      expect(connector.sent, hasLength(1));
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers');
      // The turn history is read once per subgoal and session.
      expect(history.reads, ['s1']);
    });

    test('fewer than N new fitting questions: generated, and the bank keeps '
        'growing', () async {
      final bank = await boot(
        docs: [
          _mcqDoc('a'),
          _mcqDoc('b'),
          _mcqDoc('hard', difficulty: QuestionDifficulty.hard),
          _mcqDoc('hidden', status: 'hidden'),
        ],
        minimum: 3,
        share: 1,
      );
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(4)',
            options: const ['4', 'Error'],
            correct: '4',
          ),
        ),
      );

      await tutor().requestExercise();
      await bank.idle;

      expect(connector.sent, hasLength(1));
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers');
      expect(store.docs, hasLength(5));
    });
  });

  group('the mix', () {
    test('a roll for generation does not read the bank at all', () async {
      final counting = _CountingContainer(store.container);
      await boot(
        docs: [_mcqDoc('a'), _mcqDoc('b')],
        bank: QuestionBankService(container: counting),
        minimum: 1,
        share: 0.5,
        rolls: _Rolls([0.5]),
      );
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(5)',
            options: const ['5', 'Error'],
          ),
        ),
      );

      await tutor().requestExercise();

      expect(counting.queries, 0);
      expect(history.reads, isEmpty);
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers');
    });

    test('a share of 0 in config/global switches serving off', () async {
      await boot(docs: [_mcqDoc('a')], minimum: 1, share: 0);
      planNext(
        _plan(
          ChatRequestType.mcQuestion,
          warmUp: WarmUpReview(subgoal: earlier),
        ),
      );
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(6)',
            options: const ['6', 'Error'],
          ),
        ),
      );

      await tutor().requestExercise();

      expect(connector.sent, hasLength(1));
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers');
    });

    test('a warm-up review comes from the older subgoal\'s bank with one '
        'question there, whatever N, and without a roll', () async {
      final old = _mcqDoc('old', subgoalId: 's0');
      final bank = await boot(docs: [old, _mcqDoc('s1-only')]);
      final plan = _plan(
        ChatRequestType.mcQuestion,
        warmUp: WarmUpReview(subgoal: earlier),
      );
      planNext(plan);

      await tutor().requestExercise();
      await bank.idle;

      expect(connector.sent, isEmpty);
      expect(pc!.read(activeMcqProvider)!.prompt, 'Wat drukt dit af? (old)');
      expect(stored(idOf(old)).askedCount, 2);
      expect(history.reads, ['s0']);
      verify(() => conductor.notePlannedQuestion(plan)).called(1);
    });
  });

  group('a code question from the bank', () {
    test('is put in the editor and graded by the model on the exercise\'s '
        'own exchange, like a fresh one', () async {
      final q = BankQuestion.fromResponse(
        ChatResponseFactory.fromMap({
          'type': 'complete_code',
          'prompt': 'Vul aan zodat 2 verschijnt.',
          'code': 'print(1 + ___)',
        }),
        subgoalId: 's1',
        rootGoalId: 'r1',
        targetLOIds: const ['lo-print'],
        difficulty: QuestionDifficulty.medium,
        language: 'en',
        model: 'gpt-5-mini',
        createdByUid: 'someone-else',
        createdAt: DateTime.utc(2026, 9, 20),
      )!;
      final bank = await boot(docs: [q.toMap()], minimum: 1, share: 1);
      planNext(_plan(ChatRequestType.completeCodeQuestion));

      await tutor().requestExercise();
      expect(connector.sent, isEmpty);
      expect(
        pc!.read(codeServiceProvider(SessionMode.practice)).getText(),
        'print(1 + ___)',
      );
      expect(tutorTexts(), contains('Vul aan zodat 2 verschijnt.'));

      connector.scripts.add(
        _reply(
          CodeFeedback(
            type: 'code_feedback',
            quality: AnswerQuality.correct,
            prompt: 'Goed.',
            suggestion: '',
            loSignals: const [
              LoSignal(
                subgoalId: 's1',
                loId: 'lo-print',
                kind: LoSignalKind.positive,
                strength: LoSignalStrength.moderate,
              ),
            ],
          ),
        ),
      );
      // The grade asks for the next exercise; the bank has none left.
      connector.scripts.add(
        _reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Vers',
            code: 'print(7)',
            options: const ['7', 'Error'],
          ),
        ),
      );
      await tutor().submitCode('print(1 + 1)');
      await bank.idle;

      expect(connector.sent.first.scope, PreviousInputs.exercise);
      expect(
        jsonDecode(connector.histories.first.first['content']!)['code'],
        'print(1 + ___)',
      );
      final answer = graded.single;
      expect(answer.fromAnswerKey, isFalse);
      expect(answer.signals.single.strength, LoSignalStrength.moderate);
      final record = history.records.single;
      expect(record.questionId, q.id);
      expect(record.fromBank, isTrue);
      expect(record.gradedByKey, isFalse);
      expect(stored(q.id).answeredCount, 1);
    });
  });

  group('the bank never gets in the way', () {
    MultipleChoice fresh(String tag) => MultipleChoice(
      type: 'multiple_choice',
      prompt: 'Vers $tag',
      code: 'print("$tag")',
      options: const ['a', 'b'],
    );

    test('without a `questions` container the question is generated, and '
        'the bank is left alone for the next ones', () async {
      final missing = UnprovisionedCosmos('questions');
      await boot(
        bank: QuestionBankService(container: missing.container),
        minimum: 1,
        share: 1,
        rolls: _Rolls([0, 0]),
      );
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts
        ..add(_reply(fresh('1')))
        ..add(_reply(fresh('2')));

      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers 1');
      final afterFirst = missing.requests.length;
      expect(afterFirst, greaterThan(0));

      pc!.read(activeMcqProvider.notifier).state = null;
      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers 2');
      expect(missing.requests.length, afterFirst, reason: 'backed off');
      expect(missing.writes, isEmpty);
    });

    test('a bank that does not answer costs the read timeout, once', () async {
      final silent = _SilentContainer();
      await boot(
        bank: QuestionBankService(
          container: silent,
          readTimeout: const Duration(milliseconds: 50),
        ),
        minimum: 1,
        share: 1,
        rolls: _Rolls([0, 0]),
      );
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts
        ..add(_reply(fresh('1')))
        ..add(_reply(fresh('2')));

      final watch = Stopwatch()..start();
      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers 1');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

      pc!.read(activeMcqProvider.notifier).state = null;
      await tutor().requestExercise();
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers 2');
      verify(
        () => silent.query(
          any(),
          parameters: any(named: 'parameters'),
          partitionKey: any(named: 'partitionKey'),
          crossPartition: any(named: 'crossPartition'),
        ),
      ).called(1);
    });

    test('an unreadable turn history: nothing is sure to be new, so the '
        'question is generated', () async {
      history.readError = CosmosException(503, 'Service Unavailable');
      await boot(docs: [_mcqDoc('a')], minimum: 1, share: 1);
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(fresh('1')));

      await tutor().requestExercise();

      expect(connector.sent, hasLength(1));
      expect(pc!.read(activeMcqProvider)!.prompt, 'Vers 1');
    });
  });
}
