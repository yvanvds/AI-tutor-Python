// 1A.4 — Tests `AIResponseParser` end-to-end:
// - extractAllTextStrings handles both `text: "..."` and the
//   `text: { value: "..." }` provider variant.
// - extractFirstJsonMap strips ```json``` (and bare ```) fences.
// - parse(...) returns a typed ChatResponse on the happy path and falls back
//   to ErrorResponse on empty / non-JSON / non-message / array-without-object
//   inputs.

import 'dart:convert';

import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OpenAI Responses API shape this parser handles: a list of items, each
/// of `type: "message"` with a `content` list of `output_text` chunks.
List<Map<String, dynamic>> _wrap(List<dynamic> texts) => [
      {
        'type': 'message',
        'content': [
          for (final t in texts) {'type': 'output_text', 'text': t},
        ],
      },
    ];

void main() {
  group('extractAllTextStrings', () {
    test('returns the text of each output_text chunk in order', () {
      final result = AIResponseParser.extractAllTextStrings(
        _wrap(['first', 'second']),
      );
      expect(result, ['first', 'second']);
    });

    test('accepts the `{text: {value: ...}}` provider variant', () {
      final result = AIResponseParser.extractAllTextStrings(
        _wrap([
          {'value': 'hello'},
        ]),
      );
      expect(result, ['hello']);
    });

    test('accepts a JSON string and decodes it before walking', () {
      final raw = jsonEncode(_wrap(['hi']));
      expect(AIResponseParser.extractAllTextStrings(raw), ['hi']);
    });

    test('skips items that are not type=message', () {
      final result = AIResponseParser.extractAllTextStrings([
        {'type': 'reasoning', 'content': []},
        ..._wrap(['kept']),
      ]);
      expect(result, ['kept']);
    });

    test('skips content items that are not output_text', () {
      final result = AIResponseParser.extractAllTextStrings([
        {
          'type': 'message',
          'content': [
            {'type': 'tool_call', 'text': 'ignored'},
            {'type': 'output_text', 'text': 'kept'},
          ],
        },
      ]);
      expect(result, ['kept']);
    });

    test('returns empty list for non-list, non-message input', () {
      expect(
        AIResponseParser.extractAllTextStrings({'unrelated': 1}),
        isEmpty,
      );
    });
  });

  group('extractFirstTextString', () {
    test('returns the first text', () {
      expect(
        AIResponseParser.extractFirstTextString(_wrap(['a', 'b'])),
        'a',
      );
    });

    test('returns null when there is no text chunk', () {
      expect(AIResponseParser.extractFirstTextString([]), isNull);
    });
  });

  group('extractFirstJsonMap', () {
    test('strips ```json fences before parsing', () {
      final input = _wrap([
        '```json\n{"type":"hint","prompt":"p"}\n```',
      ]);
      final m = AIResponseParser.extractFirstJsonMap(input);
      expect(m, isNotNull);
      expect(m!['type'], 'hint');
    });

    test('strips bare ``` fences too', () {
      final input = _wrap([
        '```\n{"type":"hint","prompt":"p"}\n```',
      ]);
      final m = AIResponseParser.extractFirstJsonMap(input);
      expect(m, isNotNull);
      expect(m!['prompt'], 'p');
    });

    test('parses an unfenced JSON object', () {
      final m = AIResponseParser.extractFirstJsonMap(
        _wrap(['{"type":"hint","prompt":"p"}']),
      );
      expect(m, isNotNull);
      expect(m!['type'], 'hint');
    });

    test('returns the FIRST object when the text decodes to a JSON array', () {
      final m = AIResponseParser.extractFirstJsonMap(
        _wrap(['[{"type":"hint","prompt":"a"},{"type":"hint","prompt":"b"}]']),
      );
      expect(m, isNotNull);
      expect(m!['prompt'], 'a');
    });

    test('returns null for non-JSON-looking text (no { or [)', () {
      final m = AIResponseParser.extractFirstJsonMap(_wrap(['hello world']));
      expect(m, isNull);
    });

    test('returns null on malformed JSON', () {
      final m = AIResponseParser.extractFirstJsonMap(
        _wrap(['{"type": "hint", oops']),
      );
      expect(m, isNull);
    });

    test('returns null when the array is empty', () {
      final m = AIResponseParser.extractFirstJsonMap(_wrap(['[]']));
      expect(m, isNull);
    });

    test('returns null when there is no text at all', () {
      expect(AIResponseParser.extractFirstJsonMap([]), isNull);
    });
  });

  group('parse — happy path', () {
    test('valid JSON → typed ChatResponse', () {
      final r = AIResponseParser.parse(
        _wrap(['{"type":"hint","prompt":"try a loop"}']),
      );
      expect(r, isA<Hint>());
      expect((r as Hint).prompt, 'try a loop');
    });

    test('fenced JSON → typed ChatResponse', () {
      final r = AIResponseParser.parse(
        _wrap(['```json\n{"type":"hint","prompt":"p"}\n```']),
      );
      expect(r, isA<Hint>());
    });
  });

  group('parse — fallbacks to ErrorResponse', () {
    test('empty list → "Lege respons"', () {
      final r = AIResponseParser.parse([]);
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Lege respons'));
    });

    test('no message-typed items → "Lege respons"', () {
      final r = AIResponseParser.parse([
        {'type': 'reasoning', 'content': []},
      ]);
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Lege respons'));
    });

    test('non-JSON text → "Kon respons niet verwerken: …<raw>"', () {
      final r = AIResponseParser.parse(_wrap(['just some prose']));
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Kon respons niet'));
      expect(r.message, contains('just some prose'));
    });

    test('JSON array that decodes to empty → "Kon respons niet verwerken"',
        () {
      final r = AIResponseParser.parse(_wrap(['[]']));
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Kon respons niet'));
    });

    test('JSON array of non-objects → "Kon respons niet verwerken"', () {
      // Looks like JSON, parses, but first element is not a Map.
      final r = AIResponseParser.parse(_wrap(['[1,2,3]']));
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Kon respons niet'));
    });

    test('valid JSON object with unknown type → ErrorResponse via factory',
        () {
      final r = AIResponseParser.parse(
        _wrap(['{"type":"made_up_type"}']),
      );
      expect(r, isA<ErrorResponse>());
      expect((r as ErrorResponse).message, contains('Unknown type'));
    });
  });
}
