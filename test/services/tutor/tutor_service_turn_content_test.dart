// Issue #228 — every graded turn leaves a `turn_content` doc next to its
// turn record: the question as the student saw it (the follow-up question
// for a follow-up), the answer, the feedback, the grader's own signals
// before the scope check and every one that did not count with why, where
// the student was and how the session began, and the hints asked. And it
// is best-effort like the question bank: without its container, or when it
// does not answer, the student's exercise goes on as if it were not there.
//
// The real `TutorService` and the real `TurnContentService` over an
// in-memory `turn_content` container; the connector replays canned chunks,
// the conductor is mocked and the turn history records what it is handed.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/keep_until.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
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
import 'package:ai_tutor_python/services/student_state/turn_content_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';
import '../../helpers/unprovisioned_cosmos.dart';

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

/// The school's `config/global`, as the app would have polled it.
class _Config extends GlobalConfigService {
  _Config(this.config);
  final GlobalConfig config;

  @override
  GlobalConfig? build() => config;
}

class _RecordingHistory extends TurnHistoryService {
  _RecordingHistory() : super(getUid: () => 'u1');

  final List<PersistedTurnRecord> records = [];

  @override
  Future<void> append(PersistedTurnRecord record) async => records.add(record);
}

/// A `turn_content` container that never answers.
class _SilentContainer extends MockCosmosContainer {
  _SilentContainer() {
    when(() => upsert(any(), partitionKey: any(named: 'partitionKey')))
        .thenAnswer((_) => Completer<Map<String, dynamic>>().future);
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

/// What the grader says: one signal on the asked LO and a side remark on a
/// subgoal outside the scope.
const _onTarget = LoSignal(
  subgoalId: 's1',
  loId: 'lo-1',
  kind: LoSignalKind.negative,
  strength: LoSignalStrength.moderate,
);
const _offScope = LoSignal(
  subgoalId: 's9',
  loId: 'lo-x',
  kind: LoSignalKind.positive,
  strength: LoSignalStrength.weak,
);

QuestionPlan _plan(ChatRequestType type) => QuestionPlan(
  type: type,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [_lo],
  reason: _reason,
);

List<StreamChunk> _reply(ChatResponse response) => [
  const StreamTextDelta('…'),
  StreamCompleted(response),
];

MultipleChoice _mcq() => MultipleChoice(
  type: 'multiple_choice',
  prompt: 'Wat drukt print(1 + 1) af?',
  code: 'print(1 + 1)',
  options: const ['2', '11', 'Error'],
  correct: '2',
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
    // What the conductor makes of it: the scope check's drops handed on,
    // plus one of its own, as `integrateAnswer` does.
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((inv) async {
      final answer = inv.namedArguments[#answer] as GradedAnswer;
      return TurnOutcome(
        overallQuality: answer.overallQuality,
        subgoalAdvanced: false,
        degraded: false,
        loSignals: const [],
        appliedSignals: const [],
        loStatusAfter: const [],
        subgoalProgressAfter: 0.2,
        calibrationBefore: QuestionDifficulty.medium,
        calibrationAfter: QuestionDifficulty.medium,
        hadFallback: answer.hadFallback,
        droppedSignals: [
          ...answer.droppedSignals,
          const DroppedSignal(
            GradedSignal(
              subgoalId: 's0',
              loId: 'lo-old',
              kind: LoSignalKind.neutral,
              strength: LoSignalStrength.weak,
            ),
            SignalDropReason.incidentalNeutral,
          ),
        ],
      );
    });
  });

  tearDown(() {
    pc?.dispose();
    pc = null;
    chat.dispose();
  });

  Future<TurnContentService> boot({
    CosmosContainer? container,
    GlobalConfig config = const GlobalConfig(model: 'gpt-5-mini', apiKey: ''),
  }) async {
    final contents = TurnContentService(
      container: container ?? store.container,
      getUid: () => 'u1',
    );
    final goals = MockGoalsService();
    when(() => goals.streamChildren(any())).thenAnswer((_) => Stream.empty());
    when(() => goals.getChildrenOnce(any())).thenAnswer((_) async => [active]);
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
        questionBankServiceProvider.overrideWithValue(
          QuestionBankService(container: InMemoryCosmos().container),
        ),
        turnContentServiceProvider.overrideWithValue(contents),
        globalConfigServiceProvider.overrideWith(() => _Config(config)),
      ],
    );
    // Alive, as the app keeps it (the update gate watches it).
    pc!.read(globalConfigServiceProvider);
    pc!.read(modeProvider.notifier).state = SessionMode.practice;
    pc!.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    return contents;
  }

  TutorService tutor() => pc!.read(tutorServiceProvider.notifier);

  void planNext(QuestionPlan plan) =>
      when(() => conductor.planNext()).thenAnswer((_) async => plan);

  test('a multiple-choice pick: the question with its options in the order '
      'on screen and its key, the pick, the feedback, the grader\'s signals '
      'before the check and every dropped one with why, the context, and '
      'how the session began', () async {
    final contents = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    final shown = pc!.read(activeMcqProvider)!.options;

    connector.scripts.add(
      _reply(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.wrong,
          prompt: 'Nee: 1 + 1 is een som, geen tekst.',
          loSignals: const [_onTarget, _offScope],
        ),
      ),
    );
    await tutor().submitMcqAnswer('11');
    await contents.idle;

    final record = history.records.single;
    final doc = store[record.id]!;
    expect(doc['uid'], 'u1');
    expect(doc['turnAt'], record.turnAt.toIso8601String());
    expect(doc['subgoalId'], 's1');
    expect(doc['questionType'], 'mcQuestion');
    expect(doc['isFollowUp'], isFalse);
    expect(doc['question'], {
      'text': 'Wat drukt print(1 + 1) af?',
      'code': 'print(1 + 1)',
      'options': shown,
      'correctOption': '2',
      'questionId': record.questionId,
    });
    expect(record.questionId, 's1_${BankQuestion.contentHashOf(_mcq())}');
    expect(doc['answer'], {'picked': '11'});
    expect(doc['feedback'], 'Nee: 1 + 1 is een som, geen tekst.');
    expect(doc['rawSignals'], [_onTarget.toJson(), _offScope.toJson()]);
    expect(doc['droppedSignals'], [
      {..._offScope.toJson(), 'reason': 'outOfScope'},
      {
        'subgoalId': 's0',
        'loId': 'lo-old',
        'signal': 'neutral',
        'strength': 'weak',
        'reason': 'incidentalNeutral',
      },
    ]);
    expect(doc['context'], {
      'activeRootId': 'r1',
      'activeSubgoalId': 's1',
      'selectedRootId': 'r1',
      'selectedChildId': 's1',
      'preferredRootId': null,
      'preferredChildId': null,
      'sessionStart': 'startup',
    });
    expect(doc['hintCount'], 0);
    expect(doc['ttl'], isA<int>().having((t) => t, 'ttl', greaterThan(0)));
    expect(doc['keepUntil'], isA<String>());
  });

  test('a follow-up: the follow-up question is the question, the reply the '
      'answer; the hints of the first answer are not counted again', () async {
    final contents = await boot();
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
    connector.scripts.add(_reply(Hint(type: 'hint', prompt: 'Tekst.')));
    await tutor().requestHint('print("1" + "1")');

    connector.scripts
      ..add(
        _reply(
          SocraticFeedback(
            type: 'socratic_feedback',
            quality: AnswerQuality.partial,
            prompt: 'Bijna: dat wordt 11.',
          ),
        ),
      )
      ..add(_reply(_mcq()));
    await tutor().handleStudentMessage('Ook 2.');
    await contents.idle;

    expect(history.records, hasLength(2));
    final first = store[history.records[0].id]!;
    final followUp = store[history.records[1].id]!;
    expect(first['answer'], {'picked': '2'});
    expect(first['hintCount'], 0);
    expect(followUp['isFollowUp'], isTrue);
    expect(followUp['question'], {'text': 'En print("1" + "1")?'});
    expect(followUp['answer'], {'text': 'Ook 2.'});
    expect(followUp['feedback'], 'Bijna: dat wordt 11.');
    expect(followUp['hintCount'], 1);
  });

  test('a code question: the skeleton is the question\'s code, the code '
      'handed in the answer, and the hints asked on it counted', () async {
    final contents = await boot();
    planNext(_plan(ChatRequestType.completeCodeQuestion));
    connector.scripts.add(
      _reply(
        CompleteCode(
          type: 'complete_code',
          prompt: 'Vul de som in.',
          code: 'print(1 ___ 1)',
        ),
      ),
    );
    await tutor().requestExercise();

    // Two hints before handing in.
    connector.scripts
      ..add(_reply(Hint(type: 'hint', prompt: 'Tel op.')))
      ..add(_reply(Hint(type: 'hint', prompt: 'Het is een som.')));
    await tutor().requestHint('print(1 ___ 1)');
    await tutor().requestHint('print(1 - 1)');

    connector.scripts
      ..add(
        _reply(
          CodeFeedback(
            type: 'code_feedback',
            quality: AnswerQuality.correct,
            prompt: 'Juist.',
            suggestion: '',
          ),
        ),
      )
      ..add(_reply(_mcq()));
    await tutor().submitCode('print(1 + 1)');
    await contents.idle;

    final doc = store[history.records.single.id]!;
    expect(doc['question'], {
      'text': 'Vul de som in.',
      'code': 'print(1 ___ 1)',
      'questionId': history.records.single.questionId,
    });
    expect(doc['answer'], {'code': 'print(1 + 1)'});
    expect(doc['feedback'], 'Juist.');
    expect(doc['hintCount'], 2);
  });

  test('how the session began: "Continue" in the learning path, "Work on '
      'this" on a subgoal, then the restart button', () async {
    final contents = await boot();
    planNext(_plan(ChatRequestType.mcQuestion));

    Future<String> sessionStartOfNextAnswer() async {
      connector.scripts.add(_reply(_mcq()));
      await tutor().requestExercise();
      connector.scripts.add(
        _reply(
          McqFeedback(
            type: 'mcq_feedback',
            quality: AnswerQuality.correct,
            prompt: 'Juist.',
          ),
        ),
      );
      await tutor().submitMcqAnswer('2');
      await contents.idle;
      return (store[history.records.last.id]!['context'] as Map)['sessionStart']
          as String;
    }

    await tutor().startSession(SessionStart.continueLearningPath);
    expect(await sessionStartOfNextAnswer(), 'continueLearningPath');
    pc!.read(activeMcqProvider.notifier).state = null;

    await tutor().startSession(SessionStart.workOnGoal);
    expect(await sessionStartOfNextAnswer(), 'workOnGoal');
    pc!.read(activeMcqProvider.notifier).state = null;

    await tutor().initializeSession(force: true);
    expect(await sessionStartOfNextAnswer(), 'restart');
  });

  test('kept until the day the school set in config/global', () async {
    final contents = await boot(
      config: const GlobalConfig(
        model: 'gpt-5-mini',
        apiKey: '',
        turnContentKeepUntil: KeepUntil(12, 20),
      ),
    );
    planNext(_plan(ChatRequestType.mcQuestion));
    connector.scripts.add(_reply(_mcq()));
    await tutor().requestExercise();
    connector.scripts.add(
      _reply(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      ),
    );
    await tutor().submitMcqAnswer('2');
    await contents.idle;

    final record = history.records.single;
    final until = const KeepUntil(12, 20).after(record.turnAt);
    expect(store[record.id]!['keepUntil'], until.toIso8601String());
    expect(until.month, 12);
  });

  group('best-effort', () {
    Future<void> answerAndGoOn() async {
      planNext(_plan(ChatRequestType.mcQuestion));
      connector.scripts.add(_reply(_mcq()));
      await tutor().requestExercise();
      connector.scripts.add(
        _reply(
          McqFeedback(
            type: 'mcq_feedback',
            quality: AnswerQuality.wrong,
            prompt: 'Nee.',
          ),
        ),
      );
      await tutor().submitMcqAnswer('11');
    }

    test('without a `turn_content` container the oefening goes on: graded, '
        'recorded, no error in chat', () async {
      final missing = UnprovisionedCosmos('turn_content');
      final contents = await boot(container: missing.container);
      await answerAndGoOn();
      await contents.idle;

      expect(history.records, hasLength(1));
      expect(pc!.read(activeMcqProvider)?.feedback, 'Nee.');
      expect(tutor().state, TutorState.idle);
      expect(missing.requests, isNotEmpty, reason: 'it was tried');
      final failures = chat.controller.messages
          .whereType<SystemMessage>()
          .map((m) => ChatNotice.fromJson(m.metadata?[ChatNotice.metadataKey]))
          .nonNulls
          .where((n) => n.kind == ChatNoticeKind.tutorFailed);
      expect(failures, isEmpty);
    });

    test(
      'a container that never answers does not hold the oefening up',
      () async {
        await boot(container: _SilentContainer());
        await answerAndGoOn();

        expect(history.records, hasLength(1));
        expect(pc!.read(activeMcqProvider)?.feedback, 'Nee.');
        expect(tutor().state, TutorState.idle);
      },
    );
  });
}
