// Issue #185 — every generated question lands in the question bank, and the
// graded answer to it is counted there; the turn record names the question
// it graded. And the bank is best-effort: without its container, or when it
// does not answer at all, the student's exercise goes on as if it were not
// there.
//
// The real `TutorService` and the real `QuestionBankService` over an
// in-memory `questions` container; the connector replays canned chunks, the
// conductor is mocked and the turn history records what it is handed.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
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
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';
import '../../helpers/unprovisioned_cosmos.dart';

const _model = 'gpt-5-mini';

const _usage = CallUsage(
  model: _model,
  tokens: TokenUsage(promptTokens: 900, cachedTokens: 0, completionTokens: 90),
);

/// Replays one canned chunk list per streamed request.
class _Connector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];

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
  }) => _next();

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

class _RecordingHistory extends TurnHistoryService {
  _RecordingHistory() : super(getUid: () => 'u1');

  final List<PersistedTurnRecord> records = [];

  @override
  Future<void> append(PersistedTurnRecord record) async => records.add(record);
}

/// A `questions` container that never answers.
class _SilentContainer extends MockCosmosContainer {
  _SilentContainer() {
    when(() => read(any(), partitionKey: any(named: 'partitionKey')))
        .thenAnswer((_) => Completer<Map<String, dynamic>?>().future);
  }
}

const _lo = LearningObjective(
  id: 'lo-1',
  statement: 'print a sum',
  kind: LoKind.predict,
);

const _reason = TurnSelectionReason(
  candidateLOs: [],
  chosenReason: 'test',
  notchDropFired: false,
);

const _outcome = TurnOutcome(
  overallQuality: AnswerQuality.wrong,
  subgoalAdvanced: false,
  degraded: false,
  loSignals: [],
  appliedSignals: [],
  loStatusAfter: [],
  subgoalProgressAfter: 0.2,
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  hadFallback: false,
);

QuestionPlan _plan(ChatRequestType type, {WarmUpReview? warmUp}) =>
    QuestionPlan(
      type: type,
      difficulty: QuestionDifficulty.hard,
      targetLOs: const [_lo],
      reason: _reason,
      warmUp: warmUp,
    );

List<StreamChunk> _reply(ChatResponse response, {CallUsage? usage}) => [
  const StreamTextDelta('…'),
  StreamCompleted(response, usage: usage),
];

MultipleChoice _mcq() => MultipleChoice(
  type: 'multiple_choice',
  prompt: 'Wat drukt print(1 + 1) af?',
  code: 'print(1 + 1)',
  options: const ['2', '11', 'Error'],
  correct: '2',
);

McqFeedback _mcqGrade(AnswerQuality quality, String text) =>
    McqFeedback(type: 'mcq_feedback', quality: quality, prompt: text);

SocraticQuestion _socratic(String text) =>
    SocraticQuestion(type: 'socratic_question', prompt: text);

SocraticFeedback _socraticGrade(String text, {FollowUp? followUp}) =>
    SocraticFeedback(
      type: 'socratic_feedback',
      quality: AnswerQuality.partial,
      prompt: text,
      followUp: followUp,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late _RecordingHistory history;
  late InMemoryCosmos store;
  late ChatService chat;
  ProviderContainer? pc;

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
    history = _RecordingHistory();
    store = InMemoryCosmos();
    chat = ChatService();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((_) async => _outcome);
  });

  tearDown(() {
    pc?.dispose();
    pc = null;
    chat.dispose();
  });

  /// Boots the tutor over [bank] — the in-memory one unless a test passes
  /// its own.
  Future<QuestionBankService> boot({QuestionBankService? bank}) async {
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
      ],
    );
    pc!.read(modeProvider.notifier).state = SessionMode.practice;
    pc!.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    return service;
  }

  TutorService tutor() => pc!.read(tutorServiceProvider.notifier);

  void planNext(QuestionPlan plan) =>
      when(() => conductor.planNext()).thenAnswer((_) async => plan);

  test('a generated question is stored for the plan it was asked for; the '
      'graded pick is counted on it with its feedback, and the turn record '
      'names it', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq(), usage: _usage));
    await tutor().requestExercise();
    expect(pc!.read(activeMcqProvider)?.options, hasLength(3));

    connector.scripts.add(
      _reply(_mcqGrade(AnswerQuality.wrong, 'Nee: 1 + 1 is een som.')),
    );
    await tutor().submitMcqAnswer('11');
    await bank.idle;

    expect(store.docs, hasLength(1));
    final q = BankQuestion.tryFromCosmos(store.docs.values.single)!;
    expect(q.subgoalId, 's1');
    expect(q.rootGoalId, 'r1');
    expect(q.targetLOIds, ['lo-1']);
    expect(q.questionType, ChatRequestType.mcQuestion);
    expect(q.difficulty, QuestionDifficulty.hard);
    expect(q.language, pc!.read(appLocaleProvider).languageCode);
    expect(q.model, _model);
    expect(q.createdByUid, 'u1');
    expect(q.prompt, 'Wat drukt print(1 + 1) af?');
    expect(q.options, ['2', '11', 'Error'], reason: 'as generated, unshuffled');
    expect(q.correctOption, '2');
    expect(q.askedCount, 1);
    expect(q.answeredCount, 1);
    expect(q.correctCount, 0);
    expect(q.optionFeedback.map((f) => f.toJson()), [
      {'option': '11', 'text': 'Nee: 1 + 1 is een som.', 'quality': 'wrong'},
    ]);

    expect(history.records.single.questionId, q.id);
  });

  test(
    'a question whose call reported no usage names the default model',
    () async {
      final bank = await boot();
      planNext(_plan(ChatRequestType.socraticQuestion));
      connector.scripts.add(_reply(_socratic('Waarom werkt dit?')));
      await tutor().requestExercise();
      await bank.idle;

      expect(
        BankQuestion.tryFromCosmos(store.docs.values.single)!.model,
        OpenaiConnector.defaultModel,
      );
    },
  );

  test("a follow-up's grade is not counted on the question and names no "
      'question', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.socraticQuestion));
    connector.scripts.add(_reply(_socratic('Waarom werkt dit?')));
    await tutor().requestExercise();

    connector.scripts.add(
      _reply(
        _socraticGrade(
          'Bijna.',
          followUp: const FollowUp(question: 'En zonder haakjes?'),
        ),
      ),
    );
    await tutor().handleStudentMessage('Omdat het een som is.');
    expect(tutor().state, TutorState.idle);

    connector.scripts
      ..add(_reply(_socraticGrade('Juist.')))
      // The follow-up's grade asks for the next exercise.
      ..add(_reply(_socratic('Wat doet str()?')));
    await tutor().handleStudentMessage('Dan is het een fout.');
    await bank.idle;

    expect(history.records, hasLength(2));
    final first = history.records[0];
    final followUp = history.records[1];
    expect(followUp.isFollowUp, isTrue);
    expect(followUp.questionId, isNull);

    final asked = BankQuestion.tryFromCosmos(store[first.questionId!]!)!;
    expect(asked.prompt, 'Waarom werkt dit?');
    expect(asked.answeredCount, 1);
    // ... and the next exercise is in the bank too.
    expect(store.docs, hasLength(2));
  });

  test('a warm-up question goes into the bank of the older subgoal it is '
      'about', () async {
    final bank = await boot();
    planNext(
      _plan(
        ChatRequestType.socraticQuestion,
        warmUp: WarmUpReview(subgoal: earlier),
      ),
    );
    connector.scripts.add(_reply(_socratic('Wat doet print()?')));
    await tutor().requestExercise();
    await bank.idle;

    final q = BankQuestion.tryFromCosmos(store.docs.values.single)!;
    expect(q.subgoalId, 's0');
    expect(q.rootGoalId, 'r1');
    expect(q.id, startsWith('s0_'));
  });

  group('the bank never reaches the student', () {
    Future<void> practiseOneMcq() async {
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(_mcq(), usage: _usage));
      await tutor().requestExercise();
      expect(
        pc!.read(activeMcqProvider)?.prompt,
        'Wat drukt print(1 + 1) af?',
        reason: 'the question did not reach the student',
      );

      connector.scripts.add(_reply(_mcqGrade(AnswerQuality.correct, 'Juist.')));
      await tutor().submitMcqAnswer('2');
      expect(pc!.read(activeMcqProvider)?.feedback, 'Juist.');
      expect(tutor().state, TutorState.idle);
      expect(history.records, hasLength(1));

      // "Next" still brings the next exercise.
      connector.scripts.add(_reply(_socratic('Waarom 2?')));
      await tutor().advanceFromMcq();
      expect(connector.scripts, isEmpty);
    }

    test('without a `questions` container', () async {
      final missing = UnprovisionedCosmos('questions');
      final bank = await boot(
        bank: QuestionBankService(container: missing.container),
      );

      await practiseOneMcq();
      await bank.idle;

      // The record still names the question: the id is a content hash, and
      // the bank picks it up once the container exists.
      expect(history.records.single.questionId, startsWith('s1_'));
      expect(missing.requests, isNotEmpty);
      expect(missing.writes, isEmpty);
    });

    test('when the bank does not answer at all', () async {
      final silent = _SilentContainer();
      await boot(bank: QuestionBankService(container: silent));

      await practiseOneMcq();
      verify(() => silent.read(any(), partitionKey: any(named: 'partitionKey')))
          .called(1);
    });

    test('when a bank write throws something unexpected', () async {
      final broken = MockCosmosContainer();
      when(() => broken.read(any(), partitionKey: any(named: 'partitionKey')))
          .thenThrow(CosmosException(503, 'Service Unavailable'));
      final bank = await boot(bank: QuestionBankService(container: broken));

      await practiseOneMcq();
      await bank.idle;
    });
  });
}
