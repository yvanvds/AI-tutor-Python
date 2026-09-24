// Issue #185 — the multiple-choice answer key. The `mcQuestion` instructions
// ask the model for `"correct": "A"` (the positional letter), which the
// parser used to drop. The question bank stores the key by *content*, since
// the options are shuffled before a student sees them; the grader's history
// stays as it was (`toJson` leaves the key out).

import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = ['1', '2', 'Error'];

void main() {
  group('resolveCorrect', () {
    test('a letter is a position', () {
      expect(MultipleChoice.resolveCorrect('A', _options), '1');
      expect(MultipleChoice.resolveCorrect('c', _options), 'Error');
      expect(MultipleChoice.resolveCorrect(' B) ', _options), '2');
      expect(MultipleChoice.resolveCorrect('(B)', _options), '2');
      expect(MultipleChoice.resolveCorrect('B.', _options), '2');
    });

    test('a letter wins over an option that happens to be that letter', () {
      expect(MultipleChoice.resolveCorrect('A', const ['B', 'A']), 'B');
    });

    test('the text of an option names that option', () {
      expect(MultipleChoice.resolveCorrect('Error', _options), 'Error');
      expect(MultipleChoice.resolveCorrect(' 2 ', _options), '2');
    });

    test('a letter past the last option, a number, an unknown text or '
        'nothing at all is no key', () {
      expect(MultipleChoice.resolveCorrect('D', _options), isNull);
      expect(MultipleChoice.resolveCorrect(1, _options), isNull);
      expect(MultipleChoice.resolveCorrect('Syntax error', _options), isNull);
      expect(MultipleChoice.resolveCorrect('', _options), isNull);
      expect(MultipleChoice.resolveCorrect(null, _options), isNull);
    });
  });

  test('the parser reads the key off the META', () {
    final r = AIResponseParser.parse(
      '<TEXT>Wat drukt dit af?</TEXT>'
      '<META>{"type":"multiple_choice","code":"print(1 + 1)",'
      '"options":[{"option":"1"},{"option":"2"},{"option":"11"}],'
      '"correct":"B"}</META>',
    ) as MultipleChoice;
    expect(r.correct, '2');
  });

  test('toJson — what the grader reads back in its history — leaves the key '
      'out', () {
    final r = MultipleChoice.fromMap({
      'type': 'multiple_choice',
      'prompt': 'p',
      'code': '',
      'options': [
        {'option': '1'},
        {'option': '2'},
      ],
      'correct': 'A',
    });
    expect(r.correct, '1');
    expect(r.toJson().containsKey('correct'), isFalse);
  });
}
