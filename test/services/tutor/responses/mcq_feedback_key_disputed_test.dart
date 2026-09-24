// Issue #198 — the grader of a multiple-choice pick can say the answer key
// itself is wrong: `"keyDisputed": true` in the `mcq_feedback` META, which
// `answerKeyDirective` asks for whatever the pick. The app reads it for the
// question bank; it is not part of the conversation, so `toJson` — the reply
// as it goes on the exercise's history — leaves it out.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

McqFeedback _parse(String meta) => AIResponseParser.parse(
  '<TEXT>Nee, dat klopt niet.</TEXT><META>$meta</META>',
) as McqFeedback;

void main() {
  test('the parser reads keyDisputed off the META', () {
    final r = _parse(
      '{"type":"mcq_feedback","overallQuality":"wrong","loSignals":[],'
      '"keyDisputed":true}',
    );
    expect(r.keyDisputed, isTrue);
    expect(r.quality, AnswerQuality.wrong);
    expect(r.prompt, 'Nee, dat klopt niet.');
  });

  test('absent, false, or anything but a JSON true is no dispute', () {
    for (final value in ['', ',"keyDisputed":false', ',"keyDisputed":"true"']) {
      final r = _parse(
        '{"type":"mcq_feedback","overallQuality":"wrong","loSignals":[]'
        '$value}',
      );
      expect(r.keyDisputed, isFalse, reason: value);
    }
  });

  test('the reply on the exercise\'s history does not carry it', () {
    final r = _parse(
      '{"type":"mcq_feedback","overallQuality":"wrong","loSignals":[],'
      '"keyDisputed":true}',
    );
    expect(r.toJson().containsKey('keyDisputed'), isFalse);
    expect(r.toJson()['prompt'], 'Nee, dat klopt niet.');
  });
}
