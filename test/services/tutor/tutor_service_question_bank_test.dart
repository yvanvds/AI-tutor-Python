// Issues #185 and #215 — a generated question lands in the question bank
// at its first graded answer, and only when that answer is correct: not
// when it is asked, not on a wrong or partial answer, never for a socratic
// question. The turn record names the question it graded either way. And
// the bank is best-effort: without its container, or when it does not
// answer at all, the student's exercise goes on as if it were not there.
// And #216: the question on screen carries the bank id it has or would
// have, for its short ID in the exercise header — and #256 its level, for
// the top bar.
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
import 'package:ai_tutor_python/services/tutor/exercise_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/shown_question.dart';
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

/// What the mocked conductor makes of a graded answer: its own quality.
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
  WarmUpReview? warmUp,
  QuestionDifficulty difficulty = QuestionDifficulty.hard,
  bool notchDrop = false,
}) => QuestionPlan(
  type: type,
  difficulty: difficulty,
  targetLOs: const [_lo],
  reason: notchDrop
      ? const TurnSelectionReason(
          candidateLOs: [],
          chosenReason: 'test',
          notchDropFired: true,
          notchDropRules: [NotchDropRule.strongNegatives],
        )
      : _reason,
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

SocraticFeedback _socraticGrade(
  String text, {
  AnswerQuality quality = AnswerQuality.partial,
  FollowUp? followUp,
}) => SocraticFeedback(
  type: 'socratic_feedback',
  quality: quality,
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
    ).thenAnswer(
      (inv) async => _outcome(
        (inv.namedArguments[#answer] as GradedAnswer).overallQuality,
      ),
    );
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

  test('a generated question is not stored when it is asked, only when its '
      'first answer is graded correct: for the plan it was asked for, ask '
      'and answer counted, with the feedback on the pick; the turn record '
      'names it', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq(), usage: _usage));
    final before = DateTime.now().toUtc();
    await tutor().requestExercise();
    expect(pc!.read(activeMcqProvider)?.options, hasLength(3));
    await bank.idle;
    expect(store.docs, isEmpty, reason: 'asked, not answered yet');

    connector.scripts.add(
      _reply(_mcqGrade(AnswerQuality.correct, 'Juist: 1 + 1 is 2.')),
    );
    await tutor().submitMcqAnswer('2');
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
    expect(q.correctCount, 1);
    expect(q.isActive, isTrue);
    // Asked when it was put in front of the student.
    expect(q.lastAskedAt, q.createdAt);
    expect(q.createdAt.isBefore(before), isFalse);
    expect(q.optionFeedback.map((f) => f.toJson()), [
      {'option': '2', 'text': 'Juist: 1 + 1 is 2.', 'quality': 'correct'},
    ]);

    expect(history.records.single.questionId, q.id);
  });

  test('the question on screen carries the bank id it would have from the '
      'start (#216) — the one its turn record names, stored or not — until '
      'the next question is planned or the quiz is dismissed; a socratic '
      'question has none', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    String? shown() => pc!.read(shownQuestionIdProvider);
    final first = shown();
    expect(first, 's1_${BankQuestion.contentHashOf(_mcq())}');
    expect(store.docs, isEmpty, reason: 'not in the bank, and shown anyway');

    // Answered wrong: never stored, and the ID stays with the quiz while
    // its feedback is on screen.
    connector.scripts.add(_reply(_mcqGrade(AnswerQuality.wrong, 'Nee.')));
    await tutor().submitMcqAnswer('11');
    await bank.idle;
    expect(store.docs, isEmpty);
    expect(shown(), first);
    expect(history.records.single.questionId, first);

    // The next question is planned and never arrives: the ID of the one
    // before is gone with it.
    await tutor().requestExercise();
    expect(pc!.read(activeMcqProvider), isNotNull, reason: 'still on screen');
    expect(shown(), isNull);

    final next = MultipleChoice(
      type: 'multiple_choice',
      prompt: 'En print(2 + 2)?',
      code: 'print(2 + 2)',
      options: const ['4', '22'],
      correct: '4',
    );
    connector.scripts.add(_reply(next));
    await tutor().requestExercise();
    expect(shown(), allOf(startsWith('s1_'), isNot(first)));
    expect(
      BankQuestion.shortIdOf(shown()!),
      isNot(BankQuestion.shortIdOf(first!)),
    );

    // "Next" dismisses the quiz and its ID at once, before the next
    // exercise is even planned.
    final planned = Completer<QuestionPlan>();
    when(() => conductor.planNext()).thenAnswer((_) => planned.future);
    final advancing = tutor().advanceFromMcq();
    expect(pc!.read(activeMcqProvider), isNull);
    expect(shown(), isNull);

    // A socratic question: the bank never keeps one, so it has no ID.
    connector.scripts.add(_reply(_socratic('Waarom werkt dit?')));
    planned.complete(_plan(ChatRequestType.socraticQuestion));
    await advancing;
    expect(connector.scripts, isEmpty, reason: 'the socratic question came');
    expect(shown(), isNull);
  });

  test("the question on screen carries its level for the top bar (#256): "
      "its plan's when it comes in, a notch-drop as the lower level it is, "
      'medium for a follow-up; none from when the next question is planned '
      'until it comes in, or once the quiz is dismissed', () async {
    final bank = await boot();
    ExerciseDifficulty? shown() => pc!.read(shownQuestionDifficultyProvider);
    expect(shown(), isNull, reason: 'before the first question');

    // A question at the calibration.
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    expect(
      shown(),
      const ExerciseDifficulty(QuestionDifficulty.hard, DifficultySource.plan),
    );

    // Its grade asks a follow-up: medium, whatever the question was.
    connector.scripts.add(
      _reply(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.wrong,
          prompt: 'Nee.',
          followUp: const FollowUp(question: 'En print("1" + "1")?'),
        ),
      ),
    );
    await tutor().submitMcqAnswer('11');
    expect(tutor().state, TutorState.idle);
    expect(shown(), ExerciseDifficulty.followUp);

    // The follow-up's grade asks for the next exercise, which the conductor
    // plans a notch lower for this LO.
    planNext(
      _plan(
        ChatRequestType.socraticQuestion,
        difficulty: QuestionDifficulty.medium,
        notchDrop: true,
      ),
    );
    connector.scripts
      ..add(_reply(_socraticGrade('Nee, dat wordt 11.')))
      ..add(_reply(_socratic('Wat doet str()?')));
    await tutor().handleStudentMessage('Ook 2.');
    await bank.idle;
    expect(connector.scripts, isEmpty, reason: 'the next question came');
    expect(
      shown(),
      const ExerciseDifficulty(
        QuestionDifficulty.medium,
        DifficultySource.notchDrop,
      ),
    );

    // The next question is planned and never arrives: the level of the one
    // before is gone with it.
    planNext(_plan(ChatRequestType.mcQuestion));
    await tutor().requestExercise();
    expect(shown(), isNull);

    // A quiz, then "Next": its level goes when it does.
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    expect(shown()?.source, DifficultySource.plan);
    connector.scripts.add(_reply(_mcqGrade(AnswerQuality.correct, 'Ja.')));
    await tutor().submitMcqAnswer('2');
    await bank.idle;
    final planned = Completer<QuestionPlan>();
    when(() => conductor.planNext()).thenAnswer((_) => planned.future);
    final advancing = tutor().advanceFromMcq();
    expect(shown(), isNull);
    planned.complete(_plan(ChatRequestType.mcQuestion));
    await advancing;
  });

  test('a wrong or a partial first answer stores nothing; the turn record '
      'still names the question', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    connector.scripts.add(
      _reply(_mcqGrade(AnswerQuality.wrong, 'Nee: 1 + 1 is een som.')),
    );
    await tutor().submitMcqAnswer('11');
    await bank.idle;

    expect(store.docs, isEmpty);
    final wrong = history.records.single.questionId;
    expect(wrong, startsWith('s1_'));

    // Partial is not correct (#215), as in `correctCount`.
    connector.scripts.add(
      _reply(
        MultipleChoice(
          type: 'multiple_choice',
          prompt: 'En print(2 + 2)?',
          code: 'print(2 + 2)',
          options: const ['4', '22'],
          correct: '4',
        ),
      ),
    );
    await tutor().advanceFromMcq();
    connector.scripts.add(_reply(_mcqGrade(AnswerQuality.partial, 'Bijna.')));
    await tutor().submitMcqAnswer('4');
    await bank.idle;

    expect(store.docs, isEmpty);
    expect(history.records, hasLength(2));
    expect(
      history.records[1].questionId,
      allOf(startsWith('s1_'), isNot(wrong)),
    );
  });

  test('a socratic question is never stored, not even on a correct answer; '
      'the turn record still names it', () async {
    final bank = await boot();
    planNext(_plan(ChatRequestType.socraticQuestion));
    connector.scripts.add(_reply(_socratic('Waarom werkt dit?')));
    await tutor().requestExercise();

    connector.scripts
      ..add(_reply(_socraticGrade('Juist.', quality: AnswerQuality.correct)))
      // The grade asks for the next exercise.
      ..add(_reply(_socratic('Wat doet str()?')));
    await tutor().handleStudentMessage('Omdat het een som is.');
    await bank.idle;

    expect(history.records.first.overallQuality, AnswerQuality.correct);
    expect(history.records.first.questionId, startsWith('s1_'));
    expect(store.docs, isEmpty);
  });

  test(
    'a question whose call reported no usage names the default model',
    () async {
      final bank = await boot();
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(_mcq()));
      await tutor().requestExercise();
      connector.scripts.add(_reply(_mcqGrade(AnswerQuality.correct, 'Ja.')));
      await tutor().submitMcqAnswer('2');
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
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();

    connector.scripts.add(
      _reply(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
          followUp: const FollowUp(question: 'En print("1" + "1")?'),
        ),
      ),
    );
    await tutor().submitMcqAnswer('2');
    expect(tutor().state, TutorState.idle);

    connector.scripts
      ..add(_reply(_socraticGrade('Nee, dat wordt 11.')))
      // The follow-up's grade may ask for the next exercise.
      ..add(_reply(_socratic('Wat doet str()?')));
    await tutor().handleStudentMessage('Ook 2.');
    await bank.idle;

    expect(history.records, hasLength(2));
    final first = history.records[0];
    final followUp = history.records[1];
    expect(followUp.isFollowUp, isTrue);
    expect(followUp.questionId, isNull);

    final asked = BankQuestion.tryFromCosmos(store[first.questionId!]!)!;
    expect(asked.prompt, 'Wat drukt print(1 + 1) af?');
    expect(asked.answeredCount, 1);
    expect(asked.correctCount, 1);
    expect(store.docs, hasLength(1));
  });

  test('a warm-up question goes into the bank of the older subgoal it is '
      'about', () async {
    final bank = await boot();
    planNext(
      _plan(ChatRequestType.mcQuestion, warmUp: WarmUpReview(subgoal: earlier)),
    );
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    connector.scripts.add(_reply(_mcqGrade(AnswerQuality.correct, 'Ja.')));
    await tutor().submitMcqAnswer('2');
    await bank.idle;

    final q = BankQuestion.tryFromCosmos(store.docs.values.single)!;
    expect(q.subgoalId, 's0');
    expect(q.rootGoalId, 'r1');
    expect(q.id, startsWith('s0_'));
    expect(history.records.single.questionId, q.id);
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
