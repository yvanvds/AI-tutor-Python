// Issue #254 — a generated multiple-choice question had two options with
// exactly the same text (`"omee\nt t\n"`), and that text was the key: both
// tiles turned green. Nothing compared the options. Now they are compared as
// a tile shows them — whitespace at the end of a line and empty lines at the
// end do not show — before the handler shuffles them: options that look the
// same are merged, and a question whose key looks the same as a distractor,
// or that is left with fewer than three options, is rejected like a
// blank-less exercise (#78), so the retry fetches a new one.

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:flutter_test/flutter_test.dart';

ChatResponse _parse(List<String> options, {String? correct}) =>
    ChatResponseFactory.fromMap({
      'type': 'multiple_choice',
      'prompt': 'Wat drukt dit programma af?',
      'code': 'tekst = "komeet"\nprint(tekst[1:5])\nprint(tekst[2:2])',
      'options': [
        for (final o in options) {'option': o},
      ],
      'correct': ?correct,
    });

void main() {
  group('normalizedOption — what a tile shows of an option', () {
    test('whitespace at the end of a line and empty lines at the end go', () {
      expect(MultipleChoice.normalizedOption('omee\nt t\n'), 'omee\nt t');
      expect(
        MultipleChoice.normalizedOption('omee  \nt t\n\n \n'),
        'omee\nt t',
      );
      expect(MultipleChoice.normalizedOption('a\r\nb\r\n'), 'a\nb');
    });

    test('indentation, empty lines in between and the text itself stay', () {
      expect(MultipleChoice.normalizedOption('  x\n\ny'), '  x\n\ny');
      expect(MultipleChoice.normalizedOption('Error'), 'Error');
    });
  });

  group('two options that differ only in an empty line at the end', () {
    test('are merged into the first, and the key stays on its option', () {
      final r = _parse(const [
        'omee\nt t\n',
        'omee\nt t',
        'omee\nt t\nkomeet',
        'omee\nt\n',
      ], correct: 'D');
      expect(r, isA<MultipleChoice>());
      final mcq = r as MultipleChoice;
      expect(mcq.options, ['omee\nt t\n', 'omee\nt t\nkomeet', 'omee\nt\n']);
      expect(mcq.correct, 'omee\nt\n');
      expect(mcq.options, contains(mcq.correct));
    });

    test('the question on the exercise\'s history has the merged options', () {
      final mcq = _parse(const [
        '1',
        '1\n',
        '2',
        'Error',
      ], correct: 'C') as MultipleChoice;
      expect(mcq.toJson()['options'], [
        {'option': '1'},
        {'option': '2'},
        {'option': 'Error'},
      ]);
    });

    test('the parser merges them on the envelope too', () {
      final r = AIResponseParser.parse(
        '<TEXT>Wat drukt dit af?</TEXT>'
        '<META>{"type":"multiple_choice","code":"print(1)",'
        '"options":[{"option":"1"},{"option":"1\\n"},{"option":"2"},'
        '{"option":"Error"}],"correct":"C"}</META>',
      );
      expect(r, isA<MultipleChoice>());
      expect((r as MultipleChoice).options, ['1', '2', 'Error']);
      expect(r.correct, '2');
    });
  });

  group('a question that cannot be asked is rejected for a new one', () {
    void expectRejected(ChatResponse r) {
      expect(r, isA<ErrorResponse>());
      expect(
        (r as ErrorResponse).notice?.kind,
        ChatNoticeKind.optionsLookAlike,
      );
    }

    test('the #254 question: the key looks the same as a distractor', () {
      // B and C were the same text, and B was the key.
      final r = _parse(const [
        'omee\nt t\nkomeet',
        'omee\nt t\n',
        'omee\nt t\n',
        'omee\nt\n',
      ], correct: 'B');
      expectRejected(r);
      // The log-facing message keeps the options for the bug payload.
      expect((r as ErrorResponse).message, contains('omee'));
    });

    test('the key differs from a distractor only in an empty line at the '
        'end', () {
      expectRejected(
        _parse(const [
          'omee\nt t',
          'omee\nt t\n',
          'komeet',
          'Error',
        ], correct: 'A'),
      );
    });

    test('merging leaves fewer than three options', () {
      expectRejected(_parse(const ['1', '1 ', '2'], correct: 'C'));
      expectRejected(_parse(const ['x', 'x\n'], correct: null));
    });
  });

  group('a question whose options all look different', () {
    test('comes back as it is', () {
      final r = _parse(const ['1', '2', 'Error'], correct: 'B');
      expect(r, isA<MultipleChoice>());
      expect((r as MultipleChoice).options, ['1', '2', 'Error']);
      expect(r.correct, '2');
    });

    test('also with two options: only merging may not leave fewer than '
        'three', () {
      final r = _parse(const ['True', 'False'], correct: 'A');
      expect(r, isA<MultipleChoice>());
      expect((r as MultipleChoice).options, ['True', 'False']);
    });

    test('hasLookAlikeOptions tells the two apart', () {
      expect(MultipleChoice.hasLookAlikeOptions(const ['1', '2']), isFalse);
      expect(MultipleChoice.hasLookAlikeOptions(const ['1', '1\n']), isTrue);
      expect(
        MultipleChoice.hasLookAlikeOptions(const ['a b', 'a  b']),
        isFalse,
      );
    });
  });
}
