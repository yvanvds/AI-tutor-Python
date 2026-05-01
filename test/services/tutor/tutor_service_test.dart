// 2.1 — Tests `TutorService`. The service's job is to drive a request
// through the OpenAI connector, route the parsed response to a handler, and
// keep a `state` notifier in sync. We mock the connector and conductor at
// the constructor boundary (added in this pass) and the chat/code/sound/
// report services at the locator. The InstructionGenerator is mocked too —
// its real impl is covered by 1B.1.
//
// State checks "during sendRequest" use a Completer so we can pause inside
// the request and observe the working state, then complete it and continue.
//
// Routing checks decode the input string the connector receives — every
// formatter encodes a `request_type` field, so we can assert the route
// handleStudentMessage picked.

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

class _FakeChatResponse extends Fake implements ChatResponse {}

/// Build a Responses API output payload whose first message contains the
/// JSON-encoded body for one of our typed responses.
List<Map<String, dynamic>> _outputFor(Map<String, dynamic> body) => [
      {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': jsonEncode(body)},
        ],
      },
    ];

void main() {
  late MockOpenaiConnector connector;
  late MockConductor conductor;
  late MockInstructionGenerator instrGen;
  late MockChatService chat;
  late MockCodeService code;
  late MockSoundService sound;
  late MockReportService report;

  setUpAll(() {
    registerFallbackValue(_FakeChatResponse());
    registerFallbackValue(AnswerQuality.wrong);
    registerFallbackValue(PreviousInputs.includeSession);
    registerFallbackValue(ChatRequestType.noResult);
  });

  setUp(() {
    connector = MockOpenaiConnector();
    conductor = MockConductor();
    instrGen = MockInstructionGenerator();
    chat = MockChatService();
    code = MockCodeService();
    sound = MockSoundService();
    report = MockReportService();

    when(() => instrGen.generateInstructions(any<ChatRequestType>()))
        .thenAnswer((_) async => '');
    when(() => connector.addResponse(any<ChatResponse>())).thenReturn(null);
    // Default stub: empty output decodes to ErrorResponse → ErrorResponseHandler
    // calls maybeRetry → _resendLastRequest. Tests can override.
    when(() => connector.resendRequest())
        .thenAnswer((_) async => const ConnectorOk(<dynamic>[]));
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.getNextQuestion())
        .thenReturn((ChatRequestType.noResult, QuestionDifficulty.easy));
    when(() => conductor.getGuidingUnderstanding()).thenReturn(0.0);
    when(() => conductor.updateProgress(any<AnswerQuality>()))
        .thenAnswer((_) async => true);
    when(() => conductor.guidingIsComplete(any<double>()))
        .thenAnswer((_) async => false);
    when(() => conductor.hintProvided()).thenReturn(null);

    when(() => chat.clear()).thenReturn(null);
    when(() => chat.addSystemMessage(any<String>())).thenReturn(null);
    when(() => chat.addTutorMessage(any<String>())).thenReturn(null);
    when(() => chat.addMessage(any<String>())).thenReturn(null);
    when(() => code.setText(any<String>())).thenReturn(null);
    when(() => sound.askQuestion()).thenAnswer((_) async {});
    when(() => report.updateForCurrentChildGoal(any<String>()))
        .thenAnswer((_) async {});

    registerMock<ChatService>(chat);
    registerMock<CodeService>(code);
    registerMock<SoundService>(sound);
    registerMock<ReportService>(report);
  });

  tearDown(() async {
    await resetLocator();
  });

  TutorService build() => TutorService(
        connector: connector,
        conductor: conductor,
        instructionGenerator: instrGen,
      );

  group('queryTutor — state transitions', () {
    test('idle → working while the connector is in-flight, idle after success',
        () async {
      final completer = Completer<ConnectorResult>();
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => completer.future);

      final tutor = build();
      expect(tutor.state.value, TutorState.idle);

      // Fire-and-forget — we want to inspect state mid-flight.
      final pending =
          tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      // Let queryTutor reach the `await _connector.sendRequest(...)` point.
      await Future<void>.delayed(Duration.zero);
      expect(tutor.state.value, TutorState.working);

      // Complete with an unparseable empty output → ErrorResponse → no follow-up.
      completer.complete(const ConnectorOk([]));
      await pending;
      expect(tutor.state.value, TutorState.idle);
    });

    test('queryTutor short-circuits when state is not idle', () async {
      // Pre-load with a stuck request to leave state != idle.
      final stuck = Completer<ConnectorResult>();
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) => stuck.future);

      final tutor = build();
      // Drive into working.
      // ignore: unawaited_futures
      tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      await Future<void>.delayed(Duration.zero);
      expect(tutor.state.value, TutorState.working);

      // A second call must short-circuit (no new sendRequest invocation).
      await tutor.queryTutor(
        type: ChatRequestType.studentQuestion,
        prompt: 'hi',
      );
      verify(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).called(1);

      stuck.complete(const ConnectorOk([])); // unblock the first one
    });

    test('a CodeFeedback with allowed suggestion drives state to hasFollowUp',
        () async {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => ConnectorOk(_outputFor({
            'type': 'code_feedback',
            'prompt': 'nice',
            'suggestion': 'try a list comp',
            'quality': 'correct',
          })));
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => true);

      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');

      expect(tutor.state.value, TutorState.hasFollowUp);
    });
  });

  group('queryTutor — required-arg short-circuits', () {
    test('submitCode without code: no request, state restored to idle',
        () async {
      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.submitCode);
      verifyNever(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      );
      expect(tutor.state.value, TutorState.idle);
    });

    test('mcqAnswer without prompt: no request, state restored to idle',
        () async {
      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.mcqAnswer);
      verifyNever(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      );
      expect(tutor.state.value, TutorState.idle);
    });

    test('noResult: no request, state restored to idle', () async {
      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.noResult);
      verifyNever(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      );
      expect(tutor.state.value, TutorState.idle);
    });
  });

  group('queryTutor — input formatting per request type', () {
    /// Returns (input, scope) for the single sendRequest call recorded so far.
    (String, PreviousInputs) captureSendRequest() {
      final captured = verify(
        () => connector.sendRequest(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: captureAny<PreviousInputs>(named: 'inputs'),
        ),
      ).captured;
      return (captured[0] as String, captured[1] as PreviousInputs);
    }

    setUp(() {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => const ConnectorOk([]));
    });

    test('submitCode wraps the code in a submit_code payload', () async {
      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'print(1)',
      );
      final (input, _) = captureSendRequest();
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'submit_code');
      expect(json['code'], 'print(1)');
    });

    test('mcQuestion sets newSession scope and includes difficulty', () async {
      await build().queryTutor(
        type: ChatRequestType.mcQuestion,
        difficulty: QuestionDifficulty.medium,
      );
      final (input, scope) = captureSendRequest();
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'multiple_choice');
      expect(json['difficulty'], 'medium');
      expect(scope, PreviousInputs.newSession);
    });

    test('status request uses includeAll history scope', () async {
      await build().queryTutor(type: ChatRequestType.status);
      final (_, scope) = captureSendRequest();
      expect(scope, PreviousInputs.includeAll);
    });

    test('guidingAnswer reads understanding from the conductor', () async {
      when(() => conductor.getGuidingUnderstanding()).thenReturn(0.6);
      await build().queryTutor(
        type: ChatRequestType.guidingAnswer,
        prompt: 'because',
      );
      final (input, _) = captureSendRequest();
      final json = jsonDecode(input) as Map<String, dynamic>;
      expect(json['request_type'], 'guiding_answer');
      expect(json['answer'], 'because');
      expect(json['understanding'], 0.6);
    });
  });

  group('handleStudentMessage routing', () {
    String capturedInput() {
      final captured = verify(
        () => connector.sendRequest(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).captured.single as String;
      return captured;
    }

    setUp(() {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => const ConnectorOk([]));
    });

    /// Drives a previous query whose response sets `_currentExerciseType` via
    /// the matching handler, then resets the connector mock so the next
    /// captured call corresponds to the actual student message under test.
    Future<TutorService> primeWithExerciseType(String type) async {
      final body = <String, dynamic>{
        'type': type,
        'prompt': 'p',
        'code': 'c',
        if (type == 'multiple_choice') 'options': const <Map>[],
      };
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => ConnectorOk(_outputFor(body)));

      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      // Throw away the priming call.
      clearInteractions(connector);
      // The next call needs a stub again.
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => const ConnectorOk([]));
      return tutor;
    }

    test('default (no exercise primed) → student_question', () async {
      final tutor = build();
      await tutor.handleStudentMessage('hello');
      final json = jsonDecode(capturedInput()) as Map<String, dynamic>;
      expect(json['request_type'], 'student_question');
      expect(json['question'], 'hello');
    });

    test('after MultipleChoice → mcq_answer', () async {
      final tutor = await primeWithExerciseType('multiple_choice');
      await tutor.handleStudentMessage('A');
      final json = jsonDecode(capturedInput()) as Map<String, dynamic>;
      expect(json['request_type'], 'mcq_answer');
      expect(json['answer'], 'A');
    });

    test('after SocraticQuestion → socratic_feedback', () async {
      final tutor = await primeWithExerciseType('socratic_question');
      await tutor.handleStudentMessage('because');
      final json = jsonDecode(capturedInput()) as Map<String, dynamic>;
      expect(json['request_type'], 'socratic_feedback');
    });

    test('after ExplainCode → explain_answer', () async {
      final tutor = await primeWithExerciseType('explain_code');
      await tutor.handleStudentMessage('it loops');
      final json = jsonDecode(capturedInput()) as Map<String, dynamic>;
      expect(json['request_type'], 'explain_answer');
    });

    test('after GuidingExercise → guiding_answer', () async {
      final tutor = await primeWithExerciseType('guiding_exercise');
      await tutor.handleStudentMessage('idea');
      final json = jsonDecode(capturedInput()) as Map<String, dynamic>;
      expect(json['request_type'], 'guiding_answer');
    });
  });

  group('_processResult retry policy', () {
    test('a single ConnectorFailure triggers exactly one resendRequest, then '
        'gives up', () async {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer(
        (_) async =>
            ConnectorFailure(StateError('boom'), StackTrace.current, 'boom'),
      );
      when(() => connector.resendRequest()).thenAnswer(
        (_) async =>
            ConnectorFailure(StateError('boom'), StackTrace.current, 'boom'),
      );

      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'x',
      );

      verify(() => connector.resendRequest()).called(1);
      // System message "Er ging iets mis" was added on each failure (2 in total
      // — one for the original, one for the retry).
      verify(() => chat.addSystemMessage(any<String>())).called(2);
    });

    test('a successful resend is processed normally (no second retry)',
        () async {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer(
        (_) async =>
            ConnectorFailure(StateError('boom'), StackTrace.current, 'boom'),
      );
      when(() => connector.resendRequest()).thenAnswer(
        (_) async => ConnectorOk(_outputFor({
          'type': 'answer',
          'prompt': 'recovered',
        })),
      );

      await build().queryTutor(
        type: ChatRequestType.submitCode,
        code: 'x',
      );
      verify(() => connector.resendRequest()).called(1);
      verify(() => chat.addTutorMessage('recovered')).called(1);
    });
  });

  group('requestExercise', () {
    test('noResult posts the congrats system message and skips the request',
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
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      );
    });

    test('a real next-question kicks off queryTutor with that type', () async {
      when(() => conductor.getNextQuestion())
          .thenReturn((ChatRequestType.mcQuestion, QuestionDifficulty.hard));
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => const ConnectorOk([]));

      await build().requestExercise();

      final captured = verify(
        () => connector.sendRequest(
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

  group('moveToFollowUp', () {
    test('flushes the buffered tutor message + code and returns to idle',
        () async {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => ConnectorOk(_outputFor({
            'type': 'guiding_feedback',
            'prompt': '',
            'understanding': 0.2,
            'followUp': 'next q',
            'code': 'print(1)',
          })));
      when(() => conductor.guidingIsComplete(0.2))
          .thenAnswer((_) async => false);

      final tutor = build();
      await tutor.queryTutor(type: ChatRequestType.submitCode, code: 'x');
      expect(tutor.state.value, TutorState.hasFollowUp);

      // Reset interaction counters so we can verify *only* the flush calls.
      clearInteractions(chat);
      clearInteractions(code);

      tutor.moveToFollowUp();
      expect(tutor.state.value, TutorState.idle);
      verify(() => chat.addTutorMessage('next q')).called(1);
      verify(() => code.setText('print(1)')).called(1);

      // Calling moveToFollowUp a second time must not re-emit the same buffer.
      clearInteractions(chat);
      clearInteractions(code);
      tutor.moveToFollowUp();
      verifyNever(() => chat.addTutorMessage(any<String>()));
      verifyNever(() => code.setText(any<String>()));
    });

    test('with no buffered follow-up, just returns state to idle', () {
      final tutor = build();
      tutor.moveToFollowUp();
      expect(tutor.state.value, TutorState.idle);
    });
  });

  group('requestHint / submitCode convenience wrappers', () {
    setUp(() {
      when(
        () => connector.sendRequest(
          input: any<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).thenAnswer((_) async => const ConnectorOk([]));
    });

    test('requestHint formats a request_hint payload', () async {
      await build().requestHint('print(1)');
      final captured = verify(
        () => connector.sendRequest(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).captured.single as String;
      final json = jsonDecode(captured) as Map<String, dynamic>;
      expect(json['request_type'], 'request_hint');
      expect(json['current_code'], 'print(1)');
    });

    test('submitCode delegates to queryTutor with the code', () async {
      await build().submitCode('x = 1');
      final captured = verify(
        () => connector.sendRequest(
          input: captureAny<String>(named: 'input'),
          instructions: any<String>(named: 'instructions'),
          inputs: any<PreviousInputs>(named: 'inputs'),
        ),
      ).captured.single as String;
      final json = jsonDecode(captured) as Map<String, dynamic>;
      expect(json['request_type'], 'submit_code');
      expect(json['code'], 'x = 1');
    });
  });
}
