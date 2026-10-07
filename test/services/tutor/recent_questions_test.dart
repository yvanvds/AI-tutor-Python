// Issue #184 — the recent-questions block of a question request.
//
// Question generation goes out without history, so the app keeps its own
// list of what was asked: one line per question, the last twelve, oldest
// first. Only questions go on it.
//
// Issue #244 — a line is `type | loId | code | prompt`: the code's shape
// first (one line, texts as `"…"`, no comments), then the prompt, each with
// its own cap, so a long story in the prompt can no longer push the code —
// where the exercise's structure is — off the line.

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
    test('a code question: the shape of its code, then its prompt', () {
      expect(
        RecentQuestions.describe(
          _complete(
            'Vul de stad in.',
            'stad = ___\n\nprint("Welkom in " + stad)\n',
          ),
          loId: 'lo-var',
        ),
        'complete_code | lo-var | stad = ___; print("…" + stad) | '
        'Vul de stad in.',
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
        'explain_code | lo-loop | for i in range(3):; print(i) | '
        'Wat doet dit?',
      );
      expect(
        RecentQuestions.describe(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Wat toont deze code?',
            code: "woord = 'kompas'\nprint(woord[1:4])",
            options: const ['omp', 'kom', 'mpa'],
          ),
          loId: 'lo-slice',
        ),
        'multiple_choice | lo-slice | woord = "…"; print(woord[1:4]) | '
        'Wat toont deze code?',
      );
    });

    test('the same exercise in another story has the same code, however '
        'long the story (#244)', () {
      // Two of six near-identical questions one student got in a row: each
      // story fills the old 160-character line on its own, so the model saw
      // no code at all.
      const story1 =
          'Deze code moet precies zoveel keer `klap` afdrukken als de '
          'gebruiker invoert, maar er zit een logische fout in. Vul het '
          'ontbrekende teken in. Test bijvoorbeeld met 3.';
      const story2 =
          'Deze code moet precies zoveel keer `beat` afdrukken als de '
          'gebruiker invoert. Vul het ontbrekende teken in zodat de '
          'logische fout weg is. Test daarna met 4.';
      final first = RecentQuestions.describe(
        _complete(
          story1,
          'aantal = int(input("Hoeveel klappen? "))\n'
          'teller = 1\n'
          '\n'
          'while teller ___ aantal:\n'
          '    print("klap")\n'
          '    teller = teller + 1\n',
        ),
        loId: 'fix_logic_error',
      )!;
      final second = RecentQuestions.describe(
        _complete(
          story2,
          "aantal = int(input('Hoeveel beats? '))\n"
          'teller = 1\n'
          'while teller ___ aantal:  # hier zit de fout\n'
          "    print('beat')\n"
          '    teller = teller + 1',
        ),
        loId: 'fix_logic_error',
      )!;

      const code =
          'aantal = int(input("…")); teller = 1; while teller ___ aantal:; '
          'print("…"); teller = teller + 1';
      expect(first, startsWith('complete_code | fix_logic_error | $code | '));
      expect(second, startsWith('complete_code | fix_logic_error | $code | '));
      expect(story1.length, greaterThan(RecentQuestions.maxPromptLength));
      expect(first, endsWith('…'), reason: 'the story is cut, not the code');
    });

    test('a question without code: a dash, then its prompt, whitespace '
        'folded', () {
      expect(
        RecentQuestions.describe(
          WriteCode(
            type: 'write_code',
            prompt: 'Schrijf een programma\n  dat je naam toont.',
          ),
          loId: 'lo-print',
        ),
        'write_code | lo-print | - | Schrijf een programma dat je naam toont.',
      );
      expect(
        RecentQuestions.describe(
          SocraticQuestion(
            type: 'socratic_question',
            prompt: 'Waarom zijn aanhalingstekens nodig?',
          ),
        ),
        'socratic_question | - | - | Waarom zijn aanhalingstekens nodig?',
      );
      expect(
        RecentQuestions.describe(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Welk script is juist?',
            code: '# Kies het juiste script',
            options: const ['a', 'b', 'c'],
          ),
          loId: 'lo-turtle',
        ),
        'multiple_choice | lo-turtle | - | Welk script is juist?',
        reason: 'code that is only a comment shows nothing',
      );
    });

    test('code and prompt are each cut to their own cap', () {
      final line = RecentQuestions.describe(
        _complete('Vul aan. ' * 40, 'x = x + 1\n' * 40),
        loId: 'lo-var',
      )!;
      final [_, _, code, prompt] = line.split(' | ');
      expect(code.length, RecentQuestions.maxCodeLength);
      expect(code, startsWith('x = x + 1; x = x + 1'));
      expect(code, endsWith('…'));
      expect(prompt.length, lessThanOrEqualTo(RecentQuestions.maxPromptLength));
      expect(prompt, startsWith('Vul aan. Vul aan.'));
      expect(prompt, endsWith('…'));

      final noCode = RecentQuestions.describe(
        WriteCode(type: 'write_code', prompt: 'Schrijf. ' * 40),
        loId: 'lo-var',
      )!;
      final noCodePrompt = noCode.split(' | ').last;
      expect(noCodePrompt.length, greaterThan(RecentQuestions.maxPromptLength));
      expect(
        noCodePrompt.length,
        lessThanOrEqualTo(RecentQuestions.maxPromptOnlyLength),
      );
      expect(noCodePrompt, endsWith('…'));
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

  group('codeShape (#244)', () {
    test('every string literal becomes "…", its prefix kept', () {
      expect(
        RecentQuestions.codeShape(
          'naam = "Ada"\n'
          "groet = 'Hallo, ' + naam\n"
          r'''print(f"{groet}!", r'\d')''',
        ),
        'naam = "…"; groet = "…" + naam; print(f"…", r"…")',
      );
    });

    test(
      'a quote, an escaped quote or a # inside a string stays inside it',
      () {
        expect(
          RecentQuestions.codeShape(
            'print("Jan\'s auto")\n'
            r"print('Hij zei \'ja\'')"
            '\n'
            'print("#1 # 2")',
          ),
          'print("…"); print("…"); print("…")',
        );
      },
    );

    test('a triple-quoted string is one "…", over all its lines', () {
      expect(
        RecentQuestions.codeShape(
          'tekst = """Eerste regel\n'
          "met 'quotes' en # geen commentaar\n"
          'laatste"""\n'
          'print(tekst)',
        ),
        'tekst = "…"; print(tekst)',
      );
    });

    test('comments and blank lines go, spacing is folded', () {
      expect(
        RecentQuestions.codeShape(
          '# Zorg dat munten eindigt als [9, 0]\n'
          'munten = [2,  0]\n'
          '\n'
          '___   # vul hier aan\n'
          '\r\n'
          'print(munten)\r\n',
        ),
        'munten = [2, 0]; ___; print(munten)',
      );
    });

    test('an unclosed string ends at the end of its line', () {
      expect(
        RecentQuestions.codeShape('print("open\nx = 1'),
        'print("…"; x = 1',
      );
    });

    test('nothing but comments is empty', () {
      expect(RecentQuestions.codeShape('# Kies het juiste script\n\n'), '');
      expect(RecentQuestions.codeShape(''), '');
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
    expect(recent.lines.first, 'complete_code | lo | x3 = ___ | Vraag 3.');
    expect(recent.lines.last, 'complete_code | lo | x14 = ___ | Vraag 14.');

    recent.clear();
    expect(recent.lines, isEmpty);
  });
}
