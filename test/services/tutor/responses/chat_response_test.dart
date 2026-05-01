// 1A.3 — Tests `ChatResponseFactory.fromMap` for every supported `type`
// value plus the unknown / missing fallback paths, and verifies each of the
// 14 typed response models round-trips through fromMap → toJson with focus
// on the awkward shapes (MultipleChoice's list-of-`{option:...}`,
// StatusSummary's nested `stats`, CodeFeedback's quality fallback,
// GuidingFeedback's int-or-double `understanding`).
//
// No mocks — pure fixtures.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart'
    as ans;
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
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatResponseFactory.fromMap — type dispatch', () {
    test('socratic_question', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'socratic_question',
        'prompt': 'why?',
      });
      expect(r, isA<SocraticQuestion>());
      expect((r as SocraticQuestion).prompt, 'why?');
    });

    test('multiple_choice', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'multiple_choice',
        'prompt': 'pick',
        'code': '',
        'options': [
          {'option': 'A'},
          {'option': 'B'},
        ],
      });
      expect(r, isA<MultipleChoice>());
      expect((r as MultipleChoice).options, ['A', 'B']);
    });

    test('explain_code', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'explain_code',
        'prompt': 'p',
        'code': 'c',
      });
      expect(r, isA<ExplainCode>());
    });

    test('complete_code', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'complete_code',
        'prompt': 'p',
        'code': 'c',
      });
      expect(r, isA<CompleteCode>());
    });

    test('write_code', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'write_code',
        'prompt': 'p',
      });
      expect(r, isA<WriteCode>());
    });

    test('guiding_exercise', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'guiding_exercise',
        'prompt': 'p',
        'code': 'c',
      });
      expect(r, isA<GuidingExercise>());
    });

    test('answer', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'answer',
        'prompt': 'p',
      });
      expect(r, isA<ans.Answer>());
    });

    test('hint', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'hint',
        'prompt': 'p',
      });
      expect(r, isA<Hint>());
    });

    test('code_feedback', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'code_feedback',
        'prompt': 'p',
        'suggestion': 's',
        'quality': 'correct',
      });
      expect(r, isA<CodeFeedback>());
      expect((r as CodeFeedback).quality, AnswerQuality.correct);
    });

    test('mcq_feedback', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'mcq_feedback',
        'prompt': 'p',
        'quality': 'partial',
      });
      expect(r, isA<McqFeedback>());
    });

    test('explain_feedback', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'explain_feedback',
        'prompt': 'p',
        'quality': 'wrong',
      });
      expect(r, isA<ExplainFeedback>());
    });

    test('socratic_feedback', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'socratic_feedback',
        'prompt': 'p',
        'quality': 'partial',
      });
      expect(r, isA<SocraticFeedback>());
    });

    test('guiding_feedback', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'guiding_feedback',
        'prompt': 'p',
        'understanding': 0.5,
      });
      expect(r, isA<GuidingFeedback>());
    });

    test('status_summary', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'status_summary',
        'prompt': 'p',
        'stats': {
          'hints_used': 2,
          'common_issues': ['x'],
          'last_exercise_type': 'mc',
        },
      });
      expect(r, isA<StatusSummary>());
    });

    test('error', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'error',
        'message': 'boom',
      });
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, 'boom');
    });

    test('type matching is case-insensitive (uppercase still resolves)', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'HINT',
        'prompt': 'p',
      });
      expect(r, isA<Hint>());
    });

    test('unknown type → ErrorResponse with "Unknown type: …" message', () {
      final r = ChatResponseFactory.fromMap({'type': 'made_up'});
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Unknown type'));
      expect(r.message, contains('made_up'));
    });

    test('missing type → FormatException', () {
      expect(
        () => ChatResponseFactory.fromMap({'prompt': 'no type here'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('round-trip: simple two-field models', () {
    test('Answer.fromMap → toJson preserves type+prompt', () {
      final r = ans.Answer.fromMap({'type': 'answer', 'prompt': 'hi'});
      expect(r.toJson(), {'type': 'answer', 'prompt': 'hi'});
    });

    test('Answer.fromMap defaults type to "answer" when missing', () {
      final r = ans.Answer.fromMap({'prompt': 'hi'});
      expect(r.type, 'answer');
    });

    test('Hint.fromMap → toJson preserves type+prompt', () {
      final r = Hint.fromMap({'type': 'hint', 'prompt': 'try'});
      expect(r.toJson(), {'type': 'hint', 'prompt': 'try'});
    });

    test('SocraticQuestion round-trip', () {
      final r = SocraticQuestion.fromMap({
        'type': 'socratic_question',
        'prompt': 'why?',
      });
      expect(r.toJson(), {'type': 'socratic_question', 'prompt': 'why?'});
    });

    test('WriteCode round-trip', () {
      final r = WriteCode.fromMap({'type': 'write_code', 'prompt': 'go'});
      expect(r.toJson(), {'type': 'write_code', 'prompt': 'go'});
    });
  });

  group('round-trip: code-bearing models', () {
    test('CompleteCode round-trip', () {
      final r = CompleteCode.fromMap({
        'type': 'complete_code',
        'prompt': 'fill in',
        'code': 'print(__)',
      });
      expect(r.toJson(), {
        'type': 'complete_code',
        'prompt': 'fill in',
        'code': 'print(__)',
      });
    });

    test('ExplainCode round-trip', () {
      final r = ExplainCode.fromMap({
        'type': 'explain_code',
        'prompt': 'what?',
        'code': 'print(1)',
      });
      expect(r.toJson(), {
        'type': 'explain_code',
        'prompt': 'what?',
        'code': 'print(1)',
      });
    });

    test('GuidingExercise round-trip', () {
      final r = GuidingExercise.fromMap({
        'type': 'guiding_exercise',
        'prompt': 'p',
        'code': 'c',
      });
      expect(r.toJson(), {
        'type': 'guiding_exercise',
        'prompt': 'p',
        'code': 'c',
      });
    });
  });

  group('MultipleChoice — list-of-{option:...} shape', () {
    test('decodes options from inner objects', () {
      final r = MultipleChoice.fromMap({
        'type': 'multiple_choice',
        'prompt': 'pick',
        'code': 'print(1)',
        'options': [
          {'option': 'A: 1'},
          {'option': 'B: 2'},
        ],
      });
      expect(r.options, ['A: 1', 'B: 2']);
    });

    test('toJson re-wraps each option into {option:...}', () {
      final r = MultipleChoice(
        type: 'multiple_choice',
        prompt: 'p',
        code: 'c',
        options: const ['A', 'B'],
      );
      expect(r.toJson()['options'], [
        {'option': 'A'},
        {'option': 'B'},
      ]);
    });

    test('missing options key → empty list (no crash)', () {
      final r = MultipleChoice.fromMap({
        'type': 'multiple_choice',
        'prompt': 'p',
        'code': 'c',
      });
      expect(r.options, isEmpty);
    });
  });

  group('quality decoding', () {
    test('CodeFeedback parses each quality string and round-trips', () {
      for (final (input, expected) in <(String, AnswerQuality)>[
        ('wrong', AnswerQuality.wrong),
        ('partial', AnswerQuality.partial),
        ('correct', AnswerQuality.correct),
      ]) {
        final r = CodeFeedback.fromMap({
          'type': 'code_feedback',
          'prompt': 'p',
          'suggestion': 's',
          'quality': input,
        });
        expect(r.quality, expected);
        expect(r.toJson()['quality'], expected.name);
      }
    });

    test('CodeFeedback quality decoding is case-insensitive', () {
      final r = CodeFeedback.fromMap({
        'type': 'code_feedback',
        'prompt': 'p',
        'suggestion': 's',
        'quality': 'CORRECT',
      });
      expect(r.quality, AnswerQuality.correct);
    });

    test('CodeFeedback unknown quality string defaults to wrong', () {
      final r = CodeFeedback.fromMap({
        'type': 'code_feedback',
        'prompt': 'p',
        'suggestion': 's',
        'quality': 'meh',
      });
      expect(r.quality, AnswerQuality.wrong);
    });

    test('CodeFeedback missing quality defaults to wrong', () {
      final r = CodeFeedback.fromMap({
        'type': 'code_feedback',
        'prompt': 'p',
        'suggestion': 's',
      });
      expect(r.quality, AnswerQuality.wrong);
    });

    test('McqFeedback round-trip', () {
      final r = McqFeedback.fromMap({
        'type': 'mcq_feedback',
        'prompt': 'try again',
        'quality': 'partial',
      });
      expect(r.toJson(), {
        'type': 'mcq_feedback',
        'quality': 'partial',
        'prompt': 'try again',
      });
    });
  });

  group('ExplainFeedback — followUp is optional', () {
    test('decodes followUp when present', () {
      final r = ExplainFeedback.fromMap({
        'type': 'explain_feedback',
        'prompt': 'p',
        'quality': 'correct',
        'followUp': 'next?',
      });
      expect(r.followUp, 'next?');
      expect(r.toJson()['followUp'], 'next?');
    });

    test('toJson omits followUp key when null', () {
      final r = ExplainFeedback.fromMap({
        'type': 'explain_feedback',
        'prompt': 'p',
        'quality': 'wrong',
      });
      expect(r.followUp, isNull);
      expect(r.toJson().containsKey('followUp'), isFalse);
    });

    test('toJson exports prompt under "feedback" key (not "prompt")', () {
      final r = ExplainFeedback(
        type: 'explain_feedback',
        quality: AnswerQuality.partial,
        prompt: 'p',
      );
      expect(r.toJson()['feedback'], 'p');
      expect(r.toJson().containsKey('prompt'), isFalse);
    });
  });

  group('SocraticFeedback — accepts both "follow up" and "follow_up"', () {
    test('decodes "follow up" (space variant)', () {
      final r = SocraticFeedback.fromMap({
        'type': 'socratic_feedback',
        'prompt': 'p',
        'quality': 'correct',
        'follow up': 'why?',
      });
      expect(r.followUp, 'why?');
    });

    test('decodes "follow_up" (underscore variant)', () {
      final r = SocraticFeedback.fromMap({
        'type': 'socratic_feedback',
        'prompt': 'p',
        'quality': 'correct',
        'follow_up': 'why?',
      });
      expect(r.followUp, 'why?');
    });

    test('toJson always emits "follow up" with a space', () {
      final r = SocraticFeedback(
        type: 'socratic_feedback',
        quality: AnswerQuality.correct,
        prompt: 'p',
        followUp: 'why?',
      );
      expect(r.toJson()['follow up'], 'why?');
      expect(r.toJson().containsKey('follow_up'), isFalse);
    });
  });

  group('GuidingFeedback — understanding accepts int or double', () {
    test('int understanding decodes as double', () {
      final r = GuidingFeedback.fromMap({
        'type': 'guiding_feedback',
        'prompt': 'p',
        'understanding': 1, // int
      });
      expect(r.understanding, 1.0);
      expect(r.understanding, isA<double>());
    });

    test('double understanding round-trips', () {
      final r = GuidingFeedback.fromMap({
        'type': 'guiding_feedback',
        'prompt': 'p',
        'understanding': 0.4,
        'followUp': 'fu',
        'code': 'c',
      });
      expect(r.understanding, 0.4);
      expect(r.toJson(), {
        'type': 'guiding_feedback',
        'prompt': 'p',
        'understanding': 0.4,
        'followUp': 'fu',
        'code': 'c',
      });
    });

    test('non-numeric understanding falls back to 0.0', () {
      final r = GuidingFeedback.fromMap({
        'type': 'guiding_feedback',
        'prompt': 'p',
        'understanding': 'bad',
      });
      expect(r.understanding, 0.0);
    });

    test('missing understanding falls back to 0.0', () {
      final r = GuidingFeedback.fromMap({
        'type': 'guiding_feedback',
        'prompt': 'p',
      });
      expect(r.understanding, 0.0);
    });
  });

  group('StatusSummary — nested stats', () {
    test('decodes hints_used / common_issues / last_exercise_type', () {
      final r = StatusSummary.fromMap({
        'type': 'status_summary',
        'prompt': 'doing fine',
        'stats': {
          'hints_used': 3,
          'common_issues': ['indent', 'colon'],
          'last_exercise_type': 'mc',
        },
      });
      expect(r.hintsUsed, 3);
      expect(r.commonIssues, ['indent', 'colon']);
      expect(r.lastExerciseType, 'mc');
    });

    test('missing stats → safe defaults (0 / [] / "")', () {
      final r = StatusSummary.fromMap({
        'type': 'status_summary',
        'prompt': 'p',
      });
      expect(r.hintsUsed, 0);
      expect(r.commonIssues, isEmpty);
      expect(r.lastExerciseType, '');
    });

    test('common_issues coerces non-string entries via toString()', () {
      final r = StatusSummary.fromMap({
        'type': 'status_summary',
        'prompt': 'p',
        'stats': {
          'common_issues': [1, true, 'x'],
        },
      });
      expect(r.commonIssues, ['1', 'true', 'x']);
    });

    test('toJson nests under "stats"', () {
      final r = StatusSummary(
        type: 'status_summary',
        prompt: 'p',
        hintsUsed: 1,
        commonIssues: const ['oops'],
        lastExerciseType: 'mc',
      );
      expect(r.toJson(), {
        'type': 'status_summary',
        'prompt': 'p',
        'stats': {
          'hints_used': 1,
          'common_issues': ['oops'],
          'last_exercise_type': 'mc',
        },
      });
    });
  });

  group('ErrorResponse', () {
    test('round-trip', () {
      final r = ErrorResponse.fromMap({
        'type': 'error',
        'message': 'boom',
      });
      expect(r.toJson(), {'type': 'error', 'message': 'boom'});
    });

    test('missing message defaults to "Unknown error occurred."', () {
      final r = ErrorResponse.fromMap({'type': 'error'});
      expect(r.message, 'Unknown error occurred.');
    });
  });
}
