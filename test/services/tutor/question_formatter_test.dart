// 1B.2 — Tests every static formatter on `QuestionFormatter`. Each emits a
// JSON payload with `request_type`, optionally `difficulty` (enum-name), and
// optional payload fields. Pure functions, no mocks.
//
// We decode the JSON and assert on the resulting `Map` rather than on the
// stringified form: that keeps assertions robust to key ordering while still
// pinning down every field.

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> decode(String s) =>
      jsonDecode(s) as Map<String, dynamic>;

  group('typed-difficulty questions', () {
    test('socraticQuestion emits request_type + difficulty', () {
      final m = decode(QuestionFormatter.socraticQuestion(
        QuestionDifficulty.medium,
      ));
      expect(m, {'request_type': 'socratic_question', 'difficulty': 'medium'});
    });

    test('mcQuestion', () {
      final m = decode(QuestionFormatter.mcQuestion(QuestionDifficulty.easy));
      expect(m, {'request_type': 'multiple_choice', 'difficulty': 'easy'});
    });

    test('explainCodeQuestion', () {
      final m = decode(QuestionFormatter.explainCodeQuestion(
        QuestionDifficulty.hard,
      ));
      expect(m, {'request_type': 'explain_code', 'difficulty': 'hard'});
    });

    test('completeCodeQuestion', () {
      final m = decode(QuestionFormatter.completeCodeQuestion(
        QuestionDifficulty.medium,
      ));
      expect(m, {'request_type': 'complete_code', 'difficulty': 'medium'});
    });

    test('writeCodeQuestion', () {
      final m = decode(QuestionFormatter.writeCodeQuestion(
        QuestionDifficulty.hard,
      ));
      expect(m, {'request_type': 'write_code', 'difficulty': 'hard'});
    });

    test('every QuestionDifficulty enum value renders to its plain name', () {
      for (final d in QuestionDifficulty.values) {
        final m = decode(QuestionFormatter.socraticQuestion(d));
        expect(m['difficulty'], d.name);
      }
    });
  });

  group('payload questions', () {
    test('requestHint includes current_code and no difficulty', () {
      final m = decode(QuestionFormatter.requestHint('print(x)'));
      expect(m, {
        'request_type': 'request_hint',
        'current_code': 'print(x)',
      });
      expect(m.containsKey('difficulty'), isFalse);
    });

    test('studentQuestion forwards both fields', () {
      final m = decode(QuestionFormatter.studentQuestion('what is x?', 'x=1'));
      expect(m, {
        'request_type': 'student_question',
        'question': 'what is x?',
        'code': 'x=1',
      });
    });

    test('studentQuestion with code = null produces "code": ""', () {
      final m = decode(QuestionFormatter.studentQuestion('q', null));
      expect(m, {
        'request_type': 'student_question',
        'question': 'q',
        'code': '',
      });
    });

    test('guidingAnswer carries answer + understanding (double)', () {
      final m = decode(QuestionFormatter.guidingAnswer('yes', 0.5));
      expect(m, {
        'request_type': 'guiding_answer',
        'answer': 'yes',
        'understanding': 0.5,
      });
    });

    test('explainAnswer', () {
      final m = decode(QuestionFormatter.explainAnswer('because'));
      expect(m, {'request_type': 'explain_answer', 'answer': 'because'});
    });

    test('socraticFeedback', () {
      final m = decode(QuestionFormatter.socraticFeedback('thoughts'));
      expect(m, {'request_type': 'socratic_feedback', 'answer': 'thoughts'});
    });

    test('submitCode', () {
      final m = decode(QuestionFormatter.submitCode('print("hi")'));
      expect(m, {'request_type': 'submit_code', 'code': 'print("hi")'});
    });

    test('mcqAnswer', () {
      final m = decode(QuestionFormatter.mcqAnswer('B'));
      expect(m, {'request_type': 'mcq_answer', 'answer': 'B'});
    });
  });

  group('no-payload questions', () {
    test('guidingQuestion is just request_type', () {
      final m = decode(QuestionFormatter.guidingQuestion());
      expect(m, {'request_type': 'guiding_question'});
    });

    test('status is just request_type', () {
      final m = decode(QuestionFormatter.status());
      expect(m, {'request_type': 'status'});
    });
  });

  group('output format', () {
    test('every formatter emits valid JSON whose root is an object', () {
      final samples = <String>[
        QuestionFormatter.socraticQuestion(QuestionDifficulty.easy),
        QuestionFormatter.mcQuestion(QuestionDifficulty.easy),
        QuestionFormatter.explainCodeQuestion(QuestionDifficulty.easy),
        QuestionFormatter.completeCodeQuestion(QuestionDifficulty.easy),
        QuestionFormatter.writeCodeQuestion(QuestionDifficulty.easy),
        QuestionFormatter.requestHint(''),
        QuestionFormatter.studentQuestion('q', null),
        QuestionFormatter.guidingQuestion(),
        QuestionFormatter.guidingAnswer('a', 1.0),
        QuestionFormatter.explainAnswer('a'),
        QuestionFormatter.socraticFeedback('a'),
        QuestionFormatter.submitCode('c'),
        QuestionFormatter.mcqAnswer('a'),
        QuestionFormatter.status(),
      ];
      for (final s in samples) {
        expect(jsonDecode(s), isA<Map<String, dynamic>>());
      }
    });
  });
}
