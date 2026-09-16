// #134 — which failed turns the tutor re-sends on its own.
//
// `TutorService` retries a failed request once, which is the right thing
// for a timeout or a dropped socket. A turn that failed on the account's
// key (#126) — none stored, or one OpenAI refused with a 401 — fails the
// same way when re-sent: the same key, or none, goes out again. Before
// this issue the retry ran anyway, so the student saw the same pill twice
// and the app spent a round trip on a foregone conclusion. Now such a
// turn is reported once and left alone; every other failure keeps the
// one-retry policy.
//
// The real `TutorService` over a scripted connector (canned stream chunks
// for the streamed question turns, canned results for the non-streamed
// status turn) and a mocked conductor. What is asserted is what went out
// (sends, resends), what the chat holds, and what the debug log says.

import 'dart:io';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
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
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

/// Replays one canned outcome per request, in order, and counts what the
/// tutor asked for: first sends and resends, streamed and not.
class _ScriptedConnector extends OpenaiConnector {
  final List<List<StreamChunk>> streams = [];
  final List<ConnectorResult> results = [];
  int sends = 0;
  int resends = 0;

  Stream<StreamChunk> _nextStream() {
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

  ConnectorResult _nextResult() {
    if (results.isEmpty) {
      return ConnectorFailure(
        StateError('script exhausted'),
        StackTrace.current,
        ChatNotice.raw('script exhausted'),
      );
    }
    return results.removeAt(0);
  }

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    sends++;
    return _nextStream();
  }

  @override
  Stream<StreamChunk> resendRequestStream() {
    resends++;
    return _nextStream();
  }

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    sends++;
    return _nextResult();
  }

  @override
  Future<ConnectorResult> resendRequest() async {
    resends++;
    return _nextResult();
  }
}

class _FakeInstructionGenerator extends InstructionGenerator {
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

/// Keeps the real `InstructionsService` off Cosmos.
class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

final _plan = QuestionPlan(
  type: ChatRequestType.socraticQuestion,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [
    LearningObjective(id: 'lo-1', statement: 'loops', kind: LoKind.recall),
  ],
  reason: const TurnSelectionReason(
    candidateLOs: [],
    chosenReason: 'test',
    notchDropFired: false,
  ),
);

/// A failure the way the production connector reports it: the exception
/// it caught, and the notice it derived from it.
typedef _Failure = ({String name, Object error, ChatNotice notice});

/// What OpenAI answers to a key it does not accept.
final Object _unauthorized = RequestFailedException(
  'Incorrect API key provided: sk-abc***.',
  HttpStatus.unauthorized,
);

/// The three key problems of #126, one per owner and cause.
final List<_Failure> _keyFailures = [
  (
    name: 'an own-key account with no key stored',
    error: const NoApiKeyException(OwnKey(null)),
    notice: OpenaiConnector.describeTransportError(
      const NoApiKeyException(OwnKey(null)),
    ),
  ),
  (
    name: 'an own key OpenAI refused',
    error: _unauthorized,
    notice: const ChatNotice(ChatNoticeKind.ownKeyRejected),
  ),
  (
    name: "a school key OpenAI refused",
    error: _unauthorized,
    notice: const ChatNotice(ChatNoticeKind.schoolKeyInvalid),
  ),
];

/// The failure the retry exists for: the network, not the account.
final _Failure _socketReset = (
  name: 'a dropped socket',
  error: const SocketException('reset by peer'),
  notice: OpenaiConnector.describeTransportError(
    const SocketException('reset by peer'),
  ),
);

List<StreamChunk> _question(String text) => [
  StreamTextDelta(text),
  StreamCompleted(SocraticQuestion(type: 'socratic_question', prompt: text)),
];

List<StreamChunk> _streamFailed(_Failure f) => [
  StreamFailed(f.error, StackTrace.current, f.notice),
];

ConnectorResult _callFailed(_Failure f) =>
    ConnectorFailure(f.error, StackTrace.current, f.notice);

void main() {
  // The locale the prompt is asked for comes from SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedConnector connector;
  late MockConductor conductor;
  late ChatService chat;
  late ProviderContainer pc;

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
    connector = _ScriptedConnector();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.planNext()).thenAnswer((_) async => _plan);
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
            instructionGeneratorOverride: _FakeInstructionGenerator(),
          ),
        ),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(MockGoalsService()),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  /// The "something went wrong" pills in the chat, by their cause.
  List<ChatNoticeKind?> failurePills() => chat.controller.messages
      .whereType<SystemMessage>()
      .map((m) => ChatNotice.fromJson(m.metadata?[ChatNotice.metadataKey]))
      .nonNulls
      .where((n) => n.kind == ChatNoticeKind.tutorFailed)
      .map((n) => n.cause?.kind)
      .toList();

  /// The event names the debug log kept for the last turn.
  List<String> turnEvents() => pc
      .read(debugServiceProvider)
      .buffer
      .last
      .events
      .map((e) => e.name)
      .toList();

  group('a streamed turn', () {
    for (final f in _keyFailures) {
      test(
        'that failed on ${f.name} is reported once and not re-sent',
        () async {
          connector.streams.addAll([
            _streamFailed(f),
            // Never reached: what the retry would have been answered with.
            _question('Wat doet een for-lus?'),
          ]);

          await tutor().requestExercise();

          expect(connector.sends, 1);
          expect(connector.resends, 0, reason: 'the same key would go out');
          expect(failurePills(), [f.notice.kind]);
          expect(chat.tutorMessageCount.value, 0);
          expect(tutor().state, TutorState.idle);
          expect(turnEvents(), contains('tutor.retry_skipped'));
          expect(turnEvents(), isNot(contains('tutor.maybe_retry')));
        },
      );
    }

    test('that failed on ${_socketReset.name} is still re-sent once', () async {
      connector.streams.addAll([
        _streamFailed(_socketReset),
        _question('Wat doet een for-lus?'),
      ]);

      await tutor().requestExercise();

      expect(connector.sends, 1);
      expect(connector.resends, 1);
      expect(failurePills(), [ChatNoticeKind.tutorUnreachable]);
      expect(chat.tutorMessageCount.value, 1, reason: 'the retry answered');
      expect(tutor().state, TutorState.idle);
      expect(turnEvents(), contains('tutor.maybe_retry'));
      expect(turnEvents(), isNot(contains('tutor.retry_skipped')));
    });
  });

  group('a non-streamed turn', () {
    for (final f in _keyFailures) {
      test(
        'that failed on ${f.name} is reported once and not re-sent',
        () async {
          connector.results.add(_callFailed(f));

          await tutor().queryTutor(type: ChatRequestType.status);

          expect(connector.sends, 1);
          expect(connector.resends, 0);
          expect(failurePills(), [f.notice.kind]);
          expect(tutor().state, TutorState.idle);
          expect(turnEvents(), contains('tutor.retry_skipped'));
          expect(turnEvents(), isNot(contains('tutor.maybe_retry')));
        },
      );
    }

    test(
      'that failed on ${_socketReset.name} still reaches the retry',
      () async {
        connector.results.add(_callFailed(_socketReset));

        await tutor().queryTutor(type: ChatRequestType.status);

        expect(connector.sends, 1);
        expect(failurePills(), [ChatNoticeKind.tutorUnreachable]);
        expect(tutor().state, TutorState.idle);
        // The retry is reached, not made: `_resendLastRequest` bails while
        // the turn holds `working`, so no non-streamed turn is ever re-sent
        // (#139). Only the debug log tells the two policies apart here.
        expect(turnEvents(), contains('tutor.maybe_retry'));
        expect(turnEvents(), isNot(contains('tutor.retry_skipped')));
      },
    );
  });
}
