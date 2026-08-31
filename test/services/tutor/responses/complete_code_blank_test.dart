// Issue #78 — a `complete_code` exercise whose code has nothing removed is a
// finished program the student can only stare at. It is rejected where every
// other unusable response is rejected (`ChatResponseFactory`), so the
// `ErrorResponse` handler's existing retry path fetches a real exercise
// instead of the widget rendering the broken one.
//
// The marker is `___`: the `completeCodeQuestion` instructions document tells
// the model "META.code MUST contain at least one `___` placeholder" (Cosmos;
// exported to `instructions-export.md` in this repo).

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payload attached to bug report #77: a three-line program with nothing
/// removed, which the app rendered as an exercise.
const String _finishedProgram =
    'voornaam = input("Voer uw voornaam in: ")\n'
    'achternaam = input("Voer uw achternaam in: ")\n'
    'print("Hallo, " + voornaam + " " + achternaam)';

/// The same turn done right, from the payload on #73.
const String _withBlank = '___\nprint("Welkom, " + voornaam + "!")';

ChatResponse _fromMeta(String code) => AIResponseParser.parse(
  '<TEXT>Vul het ontbrekende stuk in.</TEXT>'
  '<META>${_meta(code)}</META>',
);

String _meta(String code) =>
    '{"type":"complete_code","code":"${code.replaceAll('\n', r'\n').replaceAll('"', r'\"')}"}';

void main() {
  group('CompleteCode.hasBlank', () {
    test('the documented marker counts', () {
      expect(
        CompleteCode(
          type: 'complete_code',
          prompt: 'p',
          code: 'print(___)',
        ).hasBlank,
        isTrue,
      );
    });

    test('a longer underscore run still counts', () {
      expect(
        CompleteCode(
          type: 'complete_code',
          prompt: 'p',
          code: 'x = ______\nprint(x)',
        ).hasBlank,
        isTrue,
      );
    });

    test('a finished program does not', () {
      expect(
        CompleteCode(
          type: 'complete_code',
          prompt: 'p',
          code: _finishedProgram,
        ).hasBlank,
        isFalse,
      );
    });

    test('ordinary Python underscores are not blanks', () {
      // Rejecting these would throw away valid exercises.
      for (final code in const [
        'mijn_naam = "Sam"\nprint(mijn_naam)',
        'if __name__ == "__main__":\n    print("hi")',
        'for _ in range(3):\n    print("hoi")',
      ]) {
        expect(
          CompleteCode(type: 'complete_code', prompt: 'p', code: code).hasBlank,
          isFalse,
          reason: code,
        );
      }
    });
  });

  group('ChatResponseFactory rejects a blank-less complete_code', () {
    test('the #77 payload becomes an ErrorResponse with a typed notice', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'complete_code',
        'prompt': 'Vul het ontbrekende stuk in.',
        'code': _finishedProgram,
      });
      expect(r, isA<ErrorResponse>());
      expect(
        (r as ErrorResponse).notice?.kind,
        ChatNoticeKind.exerciseWithoutBlank,
      );
      // The log-facing message keeps the offending code for the bug payload.
      expect(r.message, contains('voornaam'));
    });

    test('a missing code field is rejected too', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'complete_code',
        'prompt': 'p',
      });
      expect(r, isA<ErrorResponse>());
      expect(
        (r as ErrorResponse).notice?.kind,
        ChatNoticeKind.exerciseWithoutBlank,
      );
    });

    test('the #73 payload is accepted unchanged', () {
      final r = ChatResponseFactory.fromMap({
        'type': 'complete_code',
        'prompt': 'p',
        'code': _withBlank,
      });
      expect(r, isA<CompleteCode>());
      expect((r as CompleteCode).code, _withBlank);
    });
  });

  group('the parser rejects it on both transports', () {
    test('envelope: blank-less META.code → exerciseWithoutBlank', () {
      final r = _fromMeta(_finishedProgram);
      expect(r, isA<ErrorResponse>());
      expect(
        (r as ErrorResponse).notice?.kind,
        ChatNoticeKind.exerciseWithoutBlank,
      );
    });

    test('envelope: a real exercise still parses', () {
      final r = _fromMeta(_withBlank);
      expect(r, isA<CompleteCode>());
      expect((r as CompleteCode).prompt, 'Vul het ontbrekende stuk in.');
      expect(r.code, _withBlank);
    });

    test('legacy JSON: blank-less code → exerciseWithoutBlank', () {
      final r = AIResponseParser.parse(
        '{"type":"complete_code","prompt":"p","code":"print(1)"}',
      );
      expect(r, isA<ErrorResponse>());
      expect(
        (r as ErrorResponse).notice?.kind,
        ChatNoticeKind.exerciseWithoutBlank,
      );
    });
  });
}
