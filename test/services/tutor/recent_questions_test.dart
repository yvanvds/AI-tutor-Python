// Issue #184 — the recent-questions block of a question request.
//
// Question generation goes out without history, so the app keeps its own
// list of what was asked: one line per question, `type | loId | core`, the
// last twelve, oldest first. Only questions go on it.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/recent_questions.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
import 'package:flutter_test/flutter_test.dart';

CompleteCode _complete(String prompt, String code) =>
    CompleteCode(type: 'complete_code', prompt: prompt, code: code);

void main() {
  group('describe', () {
    test('a code question: its prompt, then its code on one line', () {
      expect(
        RecentQuestions.describe(
          _complete(
            'Vul de stad in.',
            'stad = ___\n\nprint("Welkom in " + stad)\n',
          ),
          loId: 'lo-var',
        ),
        'complete_code | lo-var | Vul de stad in. '
        '`stad = ___; print("Welkom in " + stad)`',
      );
      expect(
        RecentQuestions.describe(
          ExplainCode(
            type: 'explain_code',
            prompt: 'Wat doet dit?',
            code: 'for i in range(3):\n    print(i)',
          ),
          loId: 'lo-loop',
        ),
        'explain_code | lo-loop | Wat doet dit? '
        '`for i in range(3):; print(i)`',
      );
    });

    test('a multiple-choice question whose prompt already shows the code '
        'names it once', () {
      expect(
        RecentQuestions.describe(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Wat toont deze code?\n\nprint("Python")',
            code: 'print("Python")',
            options: const ['Python', '"Python"', 'Error'],
          ),
          loId: 'lo-print',
        ),
        'multiple_choice | lo-print | Wat toont deze code? print("Python")',
      );
    });

    test('a question without code is its prompt, whitespace folded', () {
      expect(
        RecentQuestions.describe(
          WriteCode(
            type: 'write_code',
            prompt: 'Schrijf een programma\n  dat je naam toont.',
          ),
          loId: 'lo-print',
        ),
        'write_code | lo-print | Schrijf een programma dat je naam toont.',
      );
      expect(
        RecentQuestions.describe(
          SocraticQuestion(
            type: 'socratic_question',
            prompt: 'Waarom zijn aanhalingstekens nodig?',
          ),
        ),
        'socratic_question | - | Waarom zijn aanhalingstekens nodig?',
      );
    });

    test('a long question is cut to the cap', () {
      final line = RecentQuestions.describe(
        _complete('Vul aan. ' * 40, 'x = ___'),
        loId: 'lo-var',
      )!;
      final core = line.substring('complete_code | lo-var | '.length);
      expect(core.length, lessThanOrEqualTo(RecentQuestions.maxCoreLength));
      expect(core, endsWith('…'));
    });

    test('anything that is not a question has no line', () {
      expect(
        RecentQuestions.describe(Answer(type: 'answer', prompt: 'x')),
        isNull,
      );
      expect(RecentQuestions.describe(Hint(type: 'hint', prompt: 'x')), isNull);
      expect(
        RecentQuestions.describe(
          CodeFeedback(
            type: 'code_feedback',
            prompt: 'Goed.',
            suggestion: '',
            quality: AnswerQuality.correct,
          ),
        ),
        isNull,
      );
      expect(
        RecentQuestions.describe(
          ErrorResponse(
            type: 'error',
            message: 'complete_code without a blank',
          ),
        ),
        isNull,
      );
    });
  });

  test('keeps the last twelve questions, oldest first, and skips what is '
      'not a question', () {
    final recent = RecentQuestions();
    for (var i = 1; i <= 14; i++) {
      expect(
        recent.add(_complete('Vraag $i.', 'x$i = ___'), loId: 'lo'),
        isTrue,
      );
      expect(recent.add(Answer(type: 'answer', prompt: 'ok')), isFalse);
    }

    expect(recent.lines, hasLength(RecentQuestions.defaultCapacity));
    expect(recent.lines.first, 'complete_code | lo | Vraag 3. `x3 = ___`');
    expect(recent.lines.last, 'complete_code | lo | Vraag 14. `x14 = ___`');

    recent.clear();
    expect(recent.lines, isEmpty);
  });
}
