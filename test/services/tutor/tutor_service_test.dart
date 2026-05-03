// 2.1 — Tests `TutorService`. The service drives a request through the
// OpenAI connector (streaming for student-facing turns, one-shot for
// `status`), routes the parsed response to a handler, and keeps a `state`
// notifier in sync. We mock the connector and conductor at the constructor
// boundary and the chat/code/sound/report services via provider overrides.
//
// State checks "during sendRequest" use a Completer to pause inside the
// request and observe the working state, then complete it and continue.
//
// Routing checks decode the input string the connector receives — every
// formatter encodes a `request_type` field, so we can assert the route
// handleStudentMessage picked.

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

import '../../helpers/mocks.dart';

class _FakeChatResponse extends Fake implements ChatResponse {}

class _EmptyError implements ChatResponse {
  const _EmptyError();
  @override
  String get type => 'error';
  @override
  Map<String, dynamic> toJson() => const {'type': 'error', 'message': ''};
}

/// Stub AuthService that always returns null (no signed-in user).
class _ControlledAuth extends AuthService {
  @override
  AccountIdentity? build() => null;
}

/// Stub InstructionsService that returns an empty list.
class _StubInstructionsService extends InstructionsService {
  @override
  List<Instruction> build() => [];
  @override
  Future<List<Instruction>> getAll() async => [];
}

/// Stub GlobalConfigService that returns null.
class _NullGlobalConfig extends GlobalConfigService {
  @override
  GlobalConfig? build() => null;
}

/// Build an envelope-formatted assistant string from a typed-response body.
/// `body` must contain a `type` and a `prompt` (or, for errors, a `message`).
/// The prompt/message is moved into the `<TEXT>` section and every other
/// field stays in `<META>`.
String _envelopeFor(Map<String, dynamic> body) {
  final meta = Map<String, dynamic>.from(body);
  final text = meta.remove('prompt') ?? meta.remove('message') ?? '';
  return '<TEXT>$text</TEXT><META>${jsonEncode(meta)}</META>';
}

/// Stream that emits a single completed response with optional text deltas.
Stream<StreamChunk> _streamOf(Map<String, dynamic> body) async* {
  final text = (body['prompt'] ?? body['message'] ?? '') as String;
  if (text.isNotEmpty) yield StreamTextDelta(text);
  yield StreamCompleted(AIResponseParser.parse(_envelopeFor(body)));
}

Stream<StreamChunk> _emptyStream() async* {
  // No deltas, parser returns ErrorResponse for empty input → routes through
  // ErrorResponseHandler → maybeRetry → resendRequestStream.
  yield const StreamCompleted(_EmptyError());
}

/// Convenience to capture the input string passed to sendRequestStream.
String _capturedStreamInput(MockOpenaiConnector connector) {
  final captured = verify(
    () => connector.sendRequestStream(
      input: captureAny<String>(named: 'input'),
      instructions: any<String>(named: 'instructions'),
      inputs: any<PreviousInputs>(named: 'inputs'),
    ),
  ).captured.single as String;
  return captured;
}

void main() {
  late MockOpenaiConnector connector;
  late MockConductor conductor;
  late MockInstructionGenerator instrGen;
  late MockChatService chat;
  late MockCodeService code;
  late MockSoundService sound;
  late MockReportService report;
  late MockGoalsService goals;

  setUpAll(() {
    registerFallbackValue(_FakeChatResponse());
    registerFallbackValue(AnswerQuality.wrong);
    registerFallbackValue(PreviousInputs.includeSession);
    registerFallbackValue(ChatRequestType.noResult);
  });

  late ProviderContainer pc;

  setUp(() {
    connector = MockOpenaiConnector();
    conductor = MockConductor();
    instrGen = MockInstructionGenerator();
    chat = MockChatService();
    code = MockCodeService();
    sound = MockSoundService();
    report = MockReportService();
    goals = MockGoalsService();

    when(() => instrGen.generateInstructions(
          any<ChatRequestType>(),
          goalSelection: any(named: 'goalSelection'),
          cachedInstructions: any(named: 'cachedInstructions'),
          fetchInstructions: any(named: 'fetchInstructions'),
          fetchRootGoals: any(named: 'fetchRootGoals'),
        )).thenAnswer((_) async => '');
    when(() => connector.addResponse(any<ChatResponse>())).thenReturn(null);

    // Default stub: empty stream → ErrorResponse → ErrorResponseHandler →
    // maybeRetry → resendRequestStream. Tests can override.
    when(
      () => connector.sendRequestStream(
        input: any<String>(named: 'input'),
        instructions: any<String>(named: 'instructions'),
        inputs: any<PreviousInputs>(named: 'inputs'),
      ),
    ).thenAnswer((_) => _emptyStream());
    when(() => connector.resendRequestStream())
        .thenAnswer((_) => _emptyStream());
    // Status uses non-streaming sendRequest.
    when(
      () => connector.sendRequest(
        input: any<String>(named: 'input'),
        instructions: any<String>(named: 'instructions'),
        inputs: any<PreviousInputs>(named: 'inputs'),
      ),
    ).thenAnswer((_) async => const ConnectorOk(''));
    when(() => connector.resendRequest())
        .thenAnswer((_) async => const ConnectorOk(''));

    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.getNextQuestion())
        .thenReturn((ChatRequestType.noResult, QuestionDifficulty.easy));
    when(() => conductor.getGuidingUnderstanding()).thenReturn(0.0);
    when(() => conductor.updateProgress(any<AnswerQuality>()))
        .thenAnswer((_) async => true);
    when(() => conductor.guidingIsComplete(any<double>()))
        .thenAnswer((_) async => false);
    when(() => conductor.recordConceptAttributions(any()))
        .thenAnswer((_) async {});
    when(() => conductor.hintProvided()).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);

    when(() => chat.clear()).thenReturn(null);
    when(() => chat.addSystemMessage(any<String>())).thenReturn(null);
    when(() => chat.addTutorMessage(any<String>())).thenReturn(null);
    when(() => chat.addMessage(any<String>())).thenReturn(null);
    when(() => chat.startStream()).thenReturn(null);
    when(() => chat.updateStream(any<String>())).thenReturn(null);
    when(() => chat.completeStream(any<String>())).thenReturn(null);
    when(() => chat.failStream()).thenReturn(null);
    when(() => code.setText(any<String>())).thenReturn(null);
    when(() => sound.askQuestion()).thenAnswer((_) async {});
    when(() => report.updateForCurrentChildGoal(any<String>()))
        .thenAnswer((_) async {});

    pc = ProviderContainer(overrides: [
      tutorServiceProvider.overrideWith(() => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: instrGen,
          )),
      chatServiceProvider.overrideWithValue(chat),
      codeServiceProvider.overrideWithValue(code),
      soundServiceProvider.overrideWithValue(sound),
      reportServiceProvider.overrideWithValue(report),
      debugServiceProvider.overrideWithValue(DebugSessionRecorder()),
      authServiceProvider.overrideWith(_ControlledAuth.new),
      instructionsServiceProvider.overrideWith(_StubInstructionsService.new),
      globalConfigServiceProvider.overrideWith(_NullGlobalConfig.new),
      goalsServiceProvider.overrideWith((ref) => goals),
    ]);
  });

  tearDown(() {
    pc.dispose();
  });

  TutorService build() => pc.read(tutorServiceProvider.notifier);

  group('queryTutor — state transitions', () {
    test(
      'idle → working while the connector is in-flight, idle after success',
      () async {
        final controller = StreamController<StreamChunk>();
        when(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        ).thenAnswer((_) => controller.stream);

        final tutor = build();
        expect(pc.read(tutorServiceProvider), TutorState.idle);

        // Fire-and-forget — we want to inspect state mid-flight.
        final pending =
            tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
        await Future<void>.delayed(Duration.zero);
        expect(pc.read(tutorServiceProvider), TutorState.working);

        // Complete with an empty/error stream → ErrorResponse → no follow-up.
        controller.add(const StreamCompleted(_EmptyError()));
        await controller.close();
        await pending;
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test('queryTutor short-circuits when state is not idle', () async {
      final stuck = StreamController<StreamChunk>();
      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => stuck.stream);

      final tutor = build();
      // Drive into working.
      // ignore: unawaited_futures
      tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      await Future<void>.delayed(Duration.zero);
      expect(pc.read(tutorServiceProvider), TutorState.working);

      // A second call must short-circuit (no new stream invocation).
      await tutor.queryTutor(
        type: ChatRequestType.studentQuestion,
        prompt: 'hi',
      );
      verify(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).called(1);

      stuck.add(const StreamCompleted(_EmptyError()));
      await stuck.close();
    });

    test(
      'a CodeFeedback with allowed suggestion drives state to hasFollowUp',
      () async {
        when(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        ).thenAnswer(
          (_) => _streamOf({
            'type': 'code_feedback',
            'prompt': 'nice',
            'suggestion': 'try a list comp',
            'quality': 'correct',
          }),
        );
        when(() => conductor.updateProgress(AnswerQuality.correct))
            .thenAnswer((_) async => true);

        final tutor = build();
        await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');

        expect(pc.read(tutorServiceProvider), TutorState.hasFollowUp);
      },
    );
  });

  group('queryTutor — required-arg short-circuits', () {
    test(
      'submitCode without code: no request, state restored to idle',
      () async {
        final tutor = build();
        await tutor.queryTutor(type: ChatRequestType.submitCode);
        verifyNever(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        );
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test(
      'mcqAnswer without prompt: no request, state restored to idle',
      () async {
        final tutor = build();
        await tutor.queryTutor(type: ChatRequestType.mcqAnswer);
        verifyNever(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        );
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test('noResult: no request, state restored to idle', () async {
      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.noResult);
      verifyNever(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      );
      expect(pc.read(tutorServiceProvider), TutorState.idle);
    });
  });

  group('queryTutor — input formatting per request type', () {
    test('submitCode wraps the code in a submit_code payload', () async {
      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'print(1)',
      );
      final input = _capturedStreamInput(connector);
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'submit_code');
      expect(json['code'], 'print(1)');
    });

    test('mcQuestion sets newSession scope and includes difficulty', () async {
      await build().queryTutor(
        type: ChatRequestType.mcQuestion,
        difficulty: QuestionDifficulty.medium,
      );
      final captured = verify(
        () => connector.sendRequestStream(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: captureAny<PreviousInputs>(named: 'inputs'),
        ),
      ).captured;
      final input = captured[0] as String;
      final scope = captured[1] as PreviousInputs;
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'multiple_choice');
      expect(json['difficulty'], 'medium');
      expect(scope, PreviousInputs.newSession);
    });

    test('status request uses non-streaming sendRequest with includeAll',
        () async {
      await build().queryTutor(type: ChatRequestType.status);
      final captured = verify(
        () => connector.sendRequest(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: captureAny<PreviousInputs>(named: 'inputs'),
        ),
      ).captured;
      expect(captured[1] as PreviousInputs, PreviousInputs.includeAll);
    });

    test('guidingAnswer reads understanding from the conductor', () async {
      when(() => conductor.getGuidingUnderstanding()).thenReturn(0.6);
      await build().queryTutor(
        type: ChatRequestType.guidingAnswer,
        prompt: 'because',
      );
      final input = _capturedStreamInput(connector);
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'guiding_answer');
      expect(json['answer'], 'because');
      expect(json['understanding'], 0.6);
    });
  });

  group('handleStudentMessage routing', () {
    /// Drives a previous query whose response sets `_currentExerciseType` via
    /// the matching handler, then resets the connector mock so the next
    /// captured call corresponds to the student message under test.
    Future<TutorService> primeWithExerciseType(String type) async {
      final body = <String, dynamic>{
        'type': type,
        'prompt': 'p',
        'code': 'c',
        if (type == 'multiple_choice') 'options': const <Map>[],
      };
      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => _streamOf(body));

      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      // Throw away the priming call.
      clearInteractions(connector);
      // The next call needs a stub again.
      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => _emptyStream());
      return tutor;
    }

    test('default (no exercise primed) → student_question', () async {
      final tutor = build();
      await tutor.handleStudentMessage('hello');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'student_question');
      expect(json['question'], 'hello');
    });

    test('after MultipleChoice → mcq_answer', () async {
      final tutor = await primeWithExerciseType('multiple_choice');
      await tutor.handleStudentMessage('A');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'mcq_answer');
      expect(json['answer'], 'A');
    });

    test('after SocraticQuestion → socratic_feedback', () async {
      final tutor = await primeWithExerciseType('socratic_question');
      await tutor.handleStudentMessage('because');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'socratic_feedback');
    });

    test('after ExplainCode → explain_answer', () async {
      final tutor = await primeWithExerciseType('explain_code');
      await tutor.handleStudentMessage('it loops');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'explain_answer');
    });

    test('after GuidingExercise → guiding_answer', () async {
      final tutor = await primeWithExerciseType('guiding_exercise');
      await tutor.handleStudentMessage('idea');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'guiding_answer');
    });
  });

  group('streaming retry policy', () {
    test('a stream failure triggers exactly one resendRequestStream', () async {
      var calls = 0;
      Stream<StreamChunk> fail() async* {
        calls++;
        yield StreamFailed(StateError('boom'), StackTrace.current, 'boom');
      }

      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => fail());
      when(() => connector.resendRequestStream())
          .thenAnswer((_) => fail());

      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'x',
      );

      verify(() => connector.resendRequestStream()).called(1);
      // Both attempts produced a system error message.
      verify(() => chat.addSystemMessage(any<String>())).called(2);
      expect(calls, 2);
    });

    test('a successful resend completes the stream with the recovered text',
        () async {
      Stream<StreamChunk> failing() async* {
        yield StreamFailed(StateError('boom'), StackTrace.current, 'boom');
      }

      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => failing());
      when(() => connector.resendRequestStream()).thenAnswer(
        (_) => _streamOf({'type': 'answer', 'prompt': 'recovered'}),
      );

      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'x',
      );
      verify(() => connector.resendRequestStream()).called(1);
      verify(() => chat.completeStream('recovered')).called(1);
    });
  });

  group('requestExercise', () {
    test(
      'noResult posts the congrats system message and skips the request',
      () async {
        when(() => conductor.getNextQuestion())
            .thenReturn((ChatRequestType.noResult, QuestionDifficulty.easy));

        await build().requestExercise();

        verify(
          () => chat.addSystemMessage(
            any<String>(
              that: predicate<String>((s) => s.contains('Gefeliciteerd')),
            ),
          ),
        ).called(1);
        verifyNever(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        );
      },
    );

    test('a real next-question kicks off queryTutor with that type', () async {
      when(() => conductor.getNextQuestion())
          .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.hard));
      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => _emptyStream());

      await build().requestExercise();

      final captured = verify(
        () => connector.sendRequestStream(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).captured.single as String;
      final json = jsonDecode(captured) as Map<String, dynamic>;
      expect(json['request_type'], 'multiple_choice');
      expect(json['difficulty'], 'hard');
    });
  });

  group('requestExercise — chained from feedback handlers', () {
    /// Feeds the connector a queue of streams so we can simulate
    /// "first call returns a feedback response, second call returns the
    /// follow-up exercise". Useful for verifying the chained queryTutor
    /// from inside a feedback handler actually fires.
    void stubSendStreamSequence(List<Map<String, dynamic>> bodies) {
      var index = 0;
      when(
        () => connector.sendRequestStream(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) {
        final body = index < bodies.length
            ? bodies[index]
            : <String, dynamic>{'type': 'answer', 'prompt': ''};
        index++;
        return _streamOf(body);
      });
    }

    /// Captures every input string passed to `sendRequestStream` across all
    /// calls, decoded back to a JSON map. Order matches call order.
    List<Map<String, dynamic>> capturedRequests() {
      final captured = verify(
        () => connector.sendRequestStream(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).captured;
      return captured
          .cast<String>()
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();
    }

    test(
      'mcq_feedback chains a fresh exercise (regression: "voorbereid..." stall)',
      () async {
        // First sendRequestStream is the mcqAnswer turn → mcq_feedback.
        // Second is the next-exercise turn requested by the handler.
        stubSendStreamSequence([
          {'type': 'mcq_feedback', 'prompt': 'Goed!', 'quality': 'correct'},
          {
            'type': 'multiple_choice',
            'prompt': 'wat print dit?',
            'code': 'print(1)',
            'options': const <Map>[],
          },
        ]);
        when(() => conductor.getNextQuestion())
            .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.easy));

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.mcqAnswer,
          prompt: 'A',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[0]['request_type'], 'mcq_answer');
        expect(reqs[1]['request_type'], 'multiple_choice');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
        verify(
          () => chat.addSystemMessage(
            any<String>(
              that: predicate<String>((s) => s.contains('voorbereid')),
            ),
          ),
        ).called(1);
      },
    );

    test(
      'code_feedback without a follow-up suggestion chains a fresh exercise',
      () async {
        stubSendStreamSequence([
          {
            'type': 'code_feedback',
            'prompt': 'klopt',
            'suggestion': '',
            'quality': 'correct',
          },
          {
            'type': 'write_code',
            'prompt': 'schrijf nu zelf',
            'code': '',
          },
        ]);
        when(() => conductor.updateProgress(AnswerQuality.correct))
            .thenAnswer((_) async => true);
        when(() => conductor.getNextQuestion()).thenReturn(
          (ChatRequestType.writeCodeQuestion, QuestionDifficulty.medium),
        );

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.submitCode,
          code: 'print(1)',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[0]['request_type'], 'submit_code');
        expect(reqs[1]['request_type'], 'write_code');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test(
      'code_feedback with a denied suggestion still chains a fresh exercise',
      () async {
        stubSendStreamSequence([
          {
            'type': 'code_feedback',
            'prompt': 'klopt',
            'suggestion': 'probeer iets anders',
            'quality': 'correct',
          },
          {
            'type': 'write_code',
            'prompt': 'volgende',
            'code': '',
          },
        ]);
        // Denying the follow-up forces the requestExercise branch.
        when(() => conductor.updateProgress(AnswerQuality.correct))
            .thenAnswer((_) async => false);
        when(() => conductor.getNextQuestion()).thenReturn(
          (ChatRequestType.writeCodeQuestion, QuestionDifficulty.medium),
        );

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.submitCode,
          code: 'print(1)',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[1]['request_type'], 'write_code');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test(
      'explain_feedback without follow-up chains a fresh exercise',
      () async {
        stubSendStreamSequence([
          {
            'type': 'explain_feedback',
            'prompt': 'goed uitgelegd',
            'quality': 'correct',
          },
          {
            'type': 'multiple_choice',
            'prompt': 'volgende',
            'code': '',
            'options': const <Map>[],
          },
        ]);
        when(() => conductor.updateProgress(AnswerQuality.correct))
            .thenAnswer((_) async => true);
        when(() => conductor.getNextQuestion())
            .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.easy));

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.explainAnswer,
          prompt: 'het loopt',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[0]['request_type'], 'explain_answer');
        expect(reqs[1]['request_type'], 'multiple_choice');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test(
      'socratic_feedback without follow-up chains a fresh exercise',
      () async {
        stubSendStreamSequence([
          {
            'type': 'socratic_feedback',
            'prompt': 'mooi',
            'quality': 'correct',
          },
          {
            'type': 'multiple_choice',
            'prompt': 'volgende',
            'code': '',
            'options': const <Map>[],
          },
        ]);
        when(() => conductor.updateProgress(AnswerQuality.correct))
            .thenAnswer((_) async => true);
        when(() => conductor.getNextQuestion())
            .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.easy));

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.socraticFeedback,
          prompt: 'omdat',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[0]['request_type'], 'socratic_feedback');
        expect(reqs[1]['request_type'], 'multiple_choice');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );

    test(
      'guiding_feedback marked complete chains a fresh exercise',
      () async {
        stubSendStreamSequence([
          {
            'type': 'guiding_feedback',
            'prompt': '',
            'understanding': 0.9,
            'followUp': '',
            'code': '',
          },
          {
            'type': 'multiple_choice',
            'prompt': 'volgende',
            'code': '',
            'options': const <Map>[],
          },
        ]);
        when(() => conductor.guidingIsComplete(0.9))
            .thenAnswer((_) async => true);
        when(() => conductor.getNextQuestion())
            .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.easy));

        final tutor = build();
        await tutor.queryTutor(
          type: ChatRequestType.guidingAnswer,
          prompt: 'idee',
        );

        final reqs = capturedRequests();
        expect(reqs, hasLength(2));
        expect(reqs[1]['request_type'], 'multiple_choice');
        expect(pc.read(tutorServiceProvider), TutorState.idle);
      },
    );
  });

  group('moveToFollowUp', () {
    test(
      'flushes the buffered tutor message + code and returns to idle',
      () async {
        when(
          () => connector.sendRequestStream(
            input: any<String>(named: 'input'),
            instructions: any<String>(named: 'instructions'),
            inputs: any<PreviousInputs>(named: 'inputs'),
          ),
        ).thenAnswer(
          (_) => _streamOf({
            'type': 'guiding_feedback',
            'prompt': '',
            'understanding': 0.2,
            'followUp': 'next q',
            'code': 'print(1)',
          }),
        );
        when(() => conductor.guidingIsComplete(0.2))
            .thenAnswer((_) async => false);

        final tutor = build();
        await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
        expect(pc.read(tutorServiceProvider), TutorState.hasFollowUp);

        clearInteractions(chat);
        clearInteractions(code);

        tutor.moveToFollowUp();
        expect(pc.read(tutorServiceProvider), TutorState.idle);
        verify(() => chat.addTutorMessage('next q')).called(1);
        verify(() => code.setText('print(1)')).called(1);

        clearInteractions(chat);
        clearInteractions(code);
        tutor.moveToFollowUp();
        verifyNever(() => chat.addTutorMessage(any<String>()));
        verifyNever(() => code.setText(any<String>()));
      },
    );

    test('with no buffered follow-up, just returns state to idle', () {
      final tutor = build();
      tutor.moveToFollowUp();
      expect(pc.read(tutorServiceProvider), TutorState.idle);
    });
  });

  group('requestHint / submitCode convenience wrappers', () {
    test('requestHint formats a request_hint payload', () async {
      await build().requestHint('print(1)');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'request_hint');
      expect(json['current_code'], 'print(1)');
    });

    test('submitCode delegates to queryTutor with the code', () async {
      await build().submitCode('x = 1');
      final json =
          jsonDecode(_capturedStreamInput(connector)) as Map<String, dynamic>;
      expect(json['request_type'], 'submit_code');
      expect(json['code'], 'x = 1');
    });
  });
}
