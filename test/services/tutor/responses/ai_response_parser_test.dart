// Tests `AIResponseParser`. The parser accepts the assistant's raw text
// (chat.completions content). It tries the `<TEXT>...</TEXT><META>{...}</META>`
// envelope first, falls back to legacy JSON-only output for non-compliant
// responses, and otherwise returns an [ErrorResponse].

import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse — envelope happy path', () {
    test('TEXT becomes the prompt; META supplies the type', () {
      final r = AIResponseParser.parse(
        '<TEXT>\ntry a loop\n</TEXT>\n<META>\n{"type":"hint"}\n</META>',
      );
      expect(r, isA<Hint>());
      expect((r as Hint).prompt, 'try a loop');
    });

    test('multiple_choice keeps options inside META', () {
      final r = AIResponseParser.parse(
        '<TEXT>What does this print?</TEXT>'
        '<META>{"type":"multiple_choice","code":"print(1)",'
        '"options":[{"option":"A: 1"},{"option":"B: 2"}]}</META>',
      );
      expect(r, isA<MultipleChoice>());
      final mc = r as MultipleChoice;
      expect(mc.prompt, 'What does this print?');
      expect(mc.options, ['A: 1', 'B: 2']);
      expect(mc.code, 'print(1)');
    });

    test('error type uses TEXT as the message field', () {
      final r = AIResponseParser.parse(
        '<TEXT>kapot</TEXT><META>{"type":"error"}</META>',
      );
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, 'kapot');
    });

    test('strips ```json fences inside META', () {
      final r = AIResponseParser.parse(
        '<TEXT>p</TEXT><META>```json\n{"type":"hint"}\n```</META>',
      );
      expect(r, isA<Hint>());
    });
  });

  group('parse — legacy JSON fallback', () {
    test('plain JSON object → typed response', () {
      final r = AIResponseParser.parse('{"type":"hint","prompt":"p"}');
      expect(r, isA<Hint>());
      expect((r as Hint).prompt, 'p');
    });

    test('fenced JSON → typed response', () {
      final r = AIResponseParser.parse(
        '```json\n{"type":"hint","prompt":"p"}\n```',
      );
      expect(r, isA<Hint>());
    });

    test('JSON inside <TEXT> with malformed META still recovers', () {
      // Some models emit raw JSON in TEXT and forget META — fall through.
      final r = AIResponseParser.parse(
        '<TEXT>{"type":"hint","prompt":"p"}</TEXT><META>not json</META>',
      );
      expect(r, isA<Hint>());
      expect((r as Hint).prompt, 'p');
    });
  });

  group('parse — error fallbacks', () {
    test('empty input → "Lege respons"', () {
      final r = AIResponseParser.parse('');
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Lege respons'));
    });

    test('whitespace-only input → "Lege respons"', () {
      final r = AIResponseParser.parse('   \n\n  ');
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Lege respons'));
    });

    test('plain prose → "Kon respons niet verwerken"', () {
      final r = AIResponseParser.parse('just some prose');
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Kon respons niet'));
    });

    test('unknown type in envelope → ErrorResponse from factory', () {
      final r = AIResponseParser.parse(
        '<TEXT>x</TEXT><META>{"type":"made_up_type"}</META>',
      );
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Unknown type'));
    });
  });
}
