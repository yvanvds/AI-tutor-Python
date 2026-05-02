// 1A.2 — Tests `dispatchResponse` + the 14 response handlers in
// `response_handlers.dart`. Each handler does a small fixed routine on its
// `TutorContext` callbacks plus side effects on `Conductor`, `SoundService`
// and `ReportService` (via `DataService.sound` / `DataService.report`). The
// pattern: build a `TutorContext` whose 8 callbacks record their invocations
// in plain lists, register `MockConductor` / `MockSoundService` /
// `MockReportService` at the locator, fire `dispatchResponse`, then assert.
//
// Mocks are registered under the *interface* type so the production calls
// to `DataService.sound` / `DataService.report` resolve to them.
//
// `DataService.sound.askQuestion()` is called from many handlers; we stub it
// once in `setUp` and only `verify` it where the handler-specific contract
// asks us to.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/guiding_exercise.dart';
import 'package:ai_tutor_python/services/tutor/responses/guiding_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/response_handlers.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

import '../../../helpers/locator.dart';
import '../../../helpers/mocks.dart';

class _UnknownResponse implements ChatResponse {
  @override
  String get type => 'unknown';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}

class _Recorder {
  final List<String> startedCode = [];
  final List<String> tutorMessages = [];
  final List<String> systemMessages = [];
  final List<String> exerciseTypes = [];
  final List<({String? message, String? code})> followUps = [];
  int requestExerciseCalls = 0;
  int maybeRetryCalls = 0;
}

void main() {
  late MockConductor conductor;
  late MockSoundService sound;
  late MockReportService report;
  late _Recorder rec;
  late TutorContext ctx;

  setUpAll(() {
    registerFallbackValue(AnswerQuality.wrong);
  });

  setUp(() {
    conductor = MockConductor();
    sound = MockSoundService();
    report = MockReportService();
    rec = _Recorder();

    when(() => sound.askQuestion()).thenAnswer((_) async {});
    when(() => conductor.hintProvided()).thenReturn(null);
    when(() => conductor.updateProgress(any<AnswerQuality>()))
        .thenAnswer((_) async => true);
    when(() => conductor.guidingIsComplete(any<double>()))
        .thenAnswer((_) async => false);
    when(() => conductor.recordConceptAttributions(any()))
        .thenAnswer((_) async {});
    when(() => report.updateForCurrentChildGoal(any<String>()))
        .thenAnswer((_) async {});

    registerMock<SoundService>(sound);
    registerMock<ReportService>(report);
    registerMock<DebugSessionRecorder>(DebugSessionRecorder());

    ctx = TutorContext(
      conductor: conductor,
      startNewCode: rec.startedCode.add,
      addTutorMessage: rec.tutorMessages.add,
      addSystemMessage: rec.systemMessages.add,
      setExerciseType: rec.exerciseTypes.add,
      setFollowUp: ({String? message, String? code}) =>
          rec.followUps.add((message: message, code: code)),
      requestExercise: () async {
        rec.requestExerciseCalls++;
      },
      maybeRetry: () async {
        rec.maybeRetryCalls++;
      },
    );
  });

  tearDown(() async {
    await resetLocator();
  });

  group('dispatchResponse routes every subtype', () {
    test('CompleteCode → CompleteCodeHandler runs', () async {
      final ok = await dispatchResponse(
        CompleteCode(type: 'complete_code', prompt: 'p', code: 'c'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.exerciseTypes, ['complete_code']);
      expect(rec.startedCode, ['c']);
      expect(rec.tutorMessages, ['p']);
      verify(() => sound.askQuestion()).called(1);
    });

    test('ExplainCode → ExplainCodeHandler runs', () async {
      final ok = await dispatchResponse(
        ExplainCode(type: 'explain_code', prompt: 'p', code: 'c'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.exerciseTypes, ['explain_code']);
      expect(rec.startedCode, ['c']);
      expect(rec.tutorMessages, ['p']);
      verify(() => sound.askQuestion()).called(1);
    });

    test('WriteCode seeds a placeholder code skeleton', () async {
      final ok = await dispatchResponse(
        WriteCode(type: 'write_code', prompt: 'do x'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.exerciseTypes, ['write_code']);
      expect(rec.startedCode.single, contains('Schrijf'));
      expect(rec.tutorMessages, ['do x']);
      verify(() => sound.askQuestion()).called(1);
    });

    test('SocraticQuestion clears the editor (empty code)', () async {
      final ok = await dispatchResponse(
        SocraticQuestion(type: 'socratic_question', prompt: 'why?'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.exerciseTypes, ['socratic_question']);
      expect(rec.startedCode, ['']);
      expect(rec.tutorMessages, ['why?']);
    });

    test('MultipleChoice posts prompt + each option as a separate message',
        () async {
      final ok = await dispatchResponse(
        MultipleChoice(
          type: 'multiple_choice',
          prompt: 'pick',
          code: 'print(1)',
          options: const ['A', 'B', 'C'],
        ),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.startedCode, ['print(1)']);
      expect(rec.tutorMessages, ['pick', 'A', 'B', 'C']);
      verify(() => sound.askQuestion()).called(1);
    });

    test('GuidingExercise runs', () async {
      final ok = await dispatchResponse(
        GuidingExercise.guidingExercise(
          type: 'guiding_exercise',
          prompt: 'p',
          code: 'c',
        ),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.exerciseTypes, ['guiding_exercise']);
      expect(rec.startedCode, ['c']);
      expect(rec.tutorMessages, ['p']);
    });

    test('Answer with empty prompt is a no-op (no message, no sound)',
        () async {
      final ok = await dispatchResponse(
        Answer(type: 'answer', prompt: ''),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.tutorMessages, isEmpty);
      verifyNever(() => sound.askQuestion());
    });

    test('Answer with non-empty prompt posts it and chimes', () async {
      await dispatchResponse(
        Answer(type: 'answer', prompt: 'because pytho'),
        ctx,
      );
      expect(rec.tutorMessages, ['because pytho']);
      verify(() => sound.askQuestion()).called(1);
    });

    test('Hint posts the prompt AND increments the conductor hint counter',
        () async {
      final ok = await dispatchResponse(
        Hint(type: 'hint', prompt: 'try a loop'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.tutorMessages, ['try a loop']);
      verify(() => conductor.hintProvided()).called(1);
      verify(() => sound.askQuestion()).called(1);
    });

    test('StatusSummary forwards the prompt to ReportService', () async {
      final ok = await dispatchResponse(
        StatusSummary(
          type: 'status_summary',
          prompt: 'student is doing fine',
          hintsUsed: 1,
          commonIssues: const [],
          lastExerciseType: 'mc',
        ),
        ctx,
      );
      expect(ok, isTrue);
      verify(() => report.updateForCurrentChildGoal('student is doing fine'))
          .called(1);
    });

    test('ErrorResponse posts a system message and triggers maybeRetry',
        () async {
      final ok = await dispatchResponse(
        ErrorResponse(type: 'error', message: 'parse failed'),
        ctx,
      );
      expect(ok, isTrue);
      expect(rec.systemMessages, ['parse failed']);
      expect(rec.maybeRetryCalls, 1);
    });

    test('Unknown ChatResponse subtype → dispatchResponse returns false',
        () async {
      final ok = await dispatchResponse(_UnknownResponse(), ctx);
      expect(ok, isFalse);
      // Nothing else fired.
      expect(rec.tutorMessages, isEmpty);
      expect(rec.systemMessages, isEmpty);
      expect(rec.maybeRetryCalls, 0);
    });
  });

  group('CodeFeedbackHandler', () {
    test('correct + non-empty suggestion + suggestionAllowed=true → '
        'setFollowUp(suggestion)', () async {
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        CodeFeedback(
          type: 'code_feedback',
          prompt: 'nice work',
          suggestion: 'try a list comp',
          quality: AnswerQuality.correct,
        ),
        ctx,
      );

      expect(rec.tutorMessages, ['nice work']);
      verify(() => conductor.updateProgress(AnswerQuality.correct)).called(1);
      expect(rec.followUps, [(message: 'try a list comp', code: null)]);
      expect(rec.requestExerciseCalls, 0);
    });

    test('non-empty suggestion BUT suggestionAllowed=false → requestExercise',
        () async {
      when(() => conductor.updateProgress(AnswerQuality.partial))
          .thenAnswer((_) async => false);

      await dispatchResponse(
        CodeFeedback(
          type: 'code_feedback',
          prompt: '',
          suggestion: 'meh',
          quality: AnswerQuality.partial,
        ),
        ctx,
      );

      // Empty prompt → no tutor message, no sound.
      expect(rec.tutorMessages, isEmpty);
      verifyNever(() => sound.askQuestion());
      expect(rec.followUps, isEmpty);
      expect(rec.requestExerciseCalls, 1);
    });

    test('empty suggestion → always requestExercise (even when allowed)',
        () async {
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        CodeFeedback(
          type: 'code_feedback',
          prompt: 'p',
          suggestion: '',
          quality: AnswerQuality.correct,
        ),
        ctx,
      );

      expect(rec.followUps, isEmpty);
      expect(rec.requestExerciseCalls, 1);
    });
  });

  group('McqFeedbackHandler', () {
    test('always posts prompt, updates progress, then requestExercise',
        () async {
      await dispatchResponse(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.wrong,
          prompt: 'try again',
        ),
        ctx,
      );

      expect(rec.tutorMessages, ['try again']);
      verify(() => conductor.updateProgress(AnswerQuality.wrong)).called(1);
      verify(() => sound.askQuestion()).called(1);
      expect(rec.requestExerciseCalls, 1);
      expect(rec.followUps, isEmpty);
    });
  });

  group('ExplainFeedbackHandler', () {
    test('followUp != null AND suggestionAllowed=true → setFollowUp(message)',
        () async {
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.correct,
          prompt: 'good',
          followUp: 'now explain edge cases',
        ),
        ctx,
      );

      expect(rec.tutorMessages, ['good']);
      expect(rec.followUps, [(message: 'now explain edge cases', code: null)]);
      expect(rec.requestExerciseCalls, 0);
    });

    test('followUp == null → requestExercise (regardless of allowance)',
        () async {
      when(() => conductor.updateProgress(AnswerQuality.partial))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.partial,
          prompt: 'half right',
        ),
        ctx,
      );

      expect(rec.followUps, isEmpty);
      expect(rec.requestExerciseCalls, 1);
    });

    test('followUp != null but suggestionAllowed=false → requestExercise',
        () async {
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => false);

      await dispatchResponse(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.correct,
          prompt: 'p',
          followUp: 'next?',
        ),
        ctx,
      );

      expect(rec.followUps, isEmpty);
      expect(rec.requestExerciseCalls, 1);
    });
  });

  group('SocraticFeedbackHandler', () {
    test('mirrors ExplainFeedback branching (followUp + allowance)', () async {
      when(() => conductor.updateProgress(AnswerQuality.correct))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'good',
          followUp: 'why does that work?',
        ),
        ctx,
      );

      expect(rec.followUps, [(message: 'why does that work?', code: null)]);
      expect(rec.requestExerciseCalls, 0);
    });
  });

  group('suspectedConcepts forwarding', () {
    List<String>? lastConceptArg() {
      final captured =
          verify(() => conductor.recordConceptAttributions(captureAny()))
              .captured;
      return captured.single as List<String>?;
    }

    test('CodeFeedback with suspectedConcepts → conductor records them',
        () async {
      await dispatchResponse(
        CodeFeedback(
          type: 'code_feedback',
          prompt: 'p',
          suggestion: '',
          quality: AnswerQuality.wrong,
          suspectedConcepts: const ['variables', 'loops'],
        ),
        ctx,
      );
      expect(lastConceptArg(), ['variables', 'loops']);
    });

    test('CodeFeedback without suspectedConcepts → conductor is called with '
        'null', () async {
      await dispatchResponse(
        CodeFeedback(
          type: 'code_feedback',
          prompt: 'p',
          suggestion: '',
          quality: AnswerQuality.wrong,
        ),
        ctx,
      );
      expect(lastConceptArg(), isNull);
    });

    test('McqFeedback forwards the list when present', () async {
      await dispatchResponse(
        McqFeedback(
          type: 'mcq_feedback',
          quality: AnswerQuality.wrong,
          prompt: 'try again',
          suspectedConcepts: const ['variables'],
        ),
        ctx,
      );
      expect(lastConceptArg(), ['variables']);
    });

    test('ExplainFeedback forwards the list when present', () async {
      await dispatchResponse(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.partial,
          prompt: 'half',
          suspectedConcepts: const ['conditionals'],
        ),
        ctx,
      );
      expect(lastConceptArg(), ['conditionals']);
    });

    test('SocraticFeedback forwards the list when present', () async {
      await dispatchResponse(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.wrong,
          prompt: 'p',
          suspectedConcepts: const ['loops'],
        ),
        ctx,
      );
      expect(lastConceptArg(), ['loops']);
    });
  });

  group('GuidingFeedbackHandler', () {
    test('guidingComplete=true → requestExercise; followUp NOT set', () async {
      when(() => conductor.guidingIsComplete(0.4))
          .thenAnswer((_) async => true);

      await dispatchResponse(
        GuidingFeedback(
          type: 'guiding_feedback',
          prompt: 'good',
          understanding: 0.4,
          followUp: 'unused',
          code: 'unused',
        ),
        ctx,
      );

      expect(rec.tutorMessages, ['good']);
      expect(rec.requestExerciseCalls, 1);
      expect(rec.followUps, isEmpty);
    });

    test('guidingComplete=false → setFollowUp with non-empty message+code',
        () async {
      when(() => conductor.guidingIsComplete(0.2))
          .thenAnswer((_) async => false);

      await dispatchResponse(
        GuidingFeedback(
          type: 'guiding_feedback',
          prompt: '',
          understanding: 0.2,
          followUp: 'next q',
          code: 'print(1)',
        ),
        ctx,
      );

      // Empty prompt → no tutor message, no sound.
      expect(rec.tutorMessages, isEmpty);
      verifyNever(() => sound.askQuestion());
      expect(rec.followUps, [(message: 'next q', code: 'print(1)')]);
      expect(rec.requestExerciseCalls, 0);
    });

    test('guidingComplete=false with empty followUp/code → '
        'setFollowUp(null,null)', () async {
      when(() => conductor.guidingIsComplete(any<double>()))
          .thenAnswer((_) async => false);

      await dispatchResponse(
        GuidingFeedback(
          type: 'guiding_feedback',
          prompt: 'p',
          understanding: 0.1,
          followUp: '',
          code: '',
        ),
        ctx,
      );

      expect(rec.followUps, [(message: null, code: null)]);
    });
  });
}
