// #284 — an exercise asked for while a session is starting waits for that
// start.
//
// "Verder" in the learning path, pressed in Practice, switches to the
// session first and starts the new session after; the practice view the
// switch mounts asks for its exercise one frame later. The start's walk to
// the next subgoal empties the selection before it reads the goals and the
// progress docs, so on a slow Cosmos a plan made in between found no
// subgoal: the chat said there were no goals left, and nothing asked again.
//
// The real `TutorService` over a scripted connector and a mocked
// conductor whose `setTarget` — the walk — finishes only when the test says
// so, and whose `planNext` finds nothing until then, as the conductor does
// while the selection is empty. The end-to-end run is
// `integration_test/flows/verder_slow_cosmos.dart`.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
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
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

/// Replays one canned question per streamed request and counts the sends.
class _Connector extends OpenaiConnector {
  final List<List<StreamChunk>> streams = [];
  int sends = 0;

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    sends++;
    if (streams.isEmpty) {
      return Stream.value(
        StreamFailed(
          StateError('script exhausted'),
          StackTrace.current,
          ChatNotice.raw('script exhausted'),
        ),
      );
    }
    return Stream.fromIterable(streams.removeAt(0));
  }
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
    Goal? goalOverride,
    bool quizOpen = false,
    bool codeExerciseOpen = false,
  }) async => 'system prompt';
}

/// Keeps the real `InstructionsService` off Cosmos.
class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

/// The school's `config/global`, as the app would have polled it.
class _Config extends GlobalConfigService {
  @override
  GlobalConfig? build() => const GlobalConfig(model: 'gpt-5-mini', apiKey: '');
}

final _plan = QuestionPlan(
  type: ChatRequestType.socraticQuestion,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [
    LearningObjective(id: 'lo-1', statement: 'variables', kind: LoKind.recall),
  ],
  reason: const TurnSelectionReason(
    candidateLOs: [],
    chosenReason: 'test',
    notchDropFired: false,
  ),
);

List<StreamChunk> _question(String text) => [
  StreamTextDelta(text),
  StreamCompleted(SocraticQuestion(type: 'socratic_question', prompt: text)),
];

void main() {
  // The locale the prompt is asked for comes from SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late ChatService chat;
  late ProviderContainer pc;

  /// One per `setTarget` call, in order: the walk of that start, finished
  /// when the test completes it — with an error for a failed read.
  late List<Completer<void>> walks;

  /// Whether a walk has found the subgoal: until then the selection is
  /// empty, and a plan finds nothing.
  late bool walked;

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
    walks = [];
    walked = false;
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) {
      final walk = Completer<void>();
      walks.add(walk);
      return walk.future;
    });
    when(() => conductor.planNext())
        .thenAnswer((_) async => walked ? _plan : QuestionPlan.noResult);
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);

    final sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});

    chat = ChatService();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(
          () => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: _Generator(),
          ),
        ),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(MockGoalsService()),
        globalConfigServiceProvider.overrideWith(_Config.new),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  /// The system pills in the chat, by kind.
  List<ChatNoticeKind> pills() => chat.controller.messages
      .whereType<SystemMessage>()
      .map((m) => ChatNotice.fromJson(m.metadata?[ChatNotice.metadataKey]))
      .nonNulls
      .map((n) => n.kind)
      .toList();

  /// Lets every microtask and zero-delay timer run: whatever is not
  /// waiting for a walk gets to the end.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('an exercise asked for while "Verder" starts the session waits for '
      'its subgoal, and comes', () async {
    connector.streams.add(_question('Wat zit er in naam?'));

    final start = tutor().startSession(SessionStart.continueLearningPath);
    // The practice view "Verder" mounts asks, one frame into the walk.
    final request = tutor().requestExercise();
    await settle();

    expect(
      pills(),
      isNot(contains(ChatNoticeKind.noGoalsLeft)),
      reason: 'the exercise was planned on the empty selection of the walk',
    );
    expect(connector.sends, 0);

    walked = true;
    walks.single.complete();
    await start;
    await request;

    expect(connector.sends, 1);
    expect(chat.tutorMessageCount.value, 1);
    expect(pills(), isNot(contains(ChatNoticeKind.noGoalsLeft)));
    expect(tutor().state, TutorState.idle);
  });

  test('a restart pressed during the start is waited for too', () async {
    connector.streams.add(_question('Wat zit er in naam?'));

    final first = tutor().startSession(SessionStart.continueLearningPath);
    final request = tutor().requestExercise();
    final restart = tutor().initializeSession(force: true);
    await settle();
    expect(walks, hasLength(2));

    walked = true;
    walks.first.complete();
    await first;
    await settle();
    expect(connector.sends, 0, reason: 'the restart is still walking');

    walks.last.complete();
    await restart;
    await request;

    expect(connector.sends, 1);
    expect(chat.tutorMessageCount.value, 1);
  });

  test('a start that fails has said so, and the exercise waiting for it is '
      'not asked for', () async {
    final start = tutor().startSession(SessionStart.continueLearningPath);
    final request = tutor().requestExercise();
    await settle();

    walks.single.completeError(StateError('Cosmos did not answer'));
    await start;
    await request;

    expect(pills(), contains(ChatNoticeKind.sessionStartFailed));
    expect(
      pills(),
      isNot(contains(ChatNoticeKind.noGoalsLeft)),
      reason: 'a failed start is not the end of the curriculum',
    );
    expect(connector.sends, 0);
  });

  test('with no start in progress, an exercise is asked for at once', () async {
    walked = true;
    connector.streams.add(_question('Wat zit er in naam?'));

    await tutor().requestExercise();

    expect(connector.sends, 1);
    expect(walks, isEmpty);
  });
}
