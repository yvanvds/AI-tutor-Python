// Issue #147 — a reply whose prose carries a run of characters from an
// alphabet the tutor does not write in is refused, not shown.
//
// Both call shapes: the streamed turns a student sees a question and its
// feedback on, and the non-streamed grader/status turns. Streaming goes
// through `assembleStream` over a scripted delta stream; the non-streamed
// one goes over the real `sendRequest` against a scripted HTTP client, so
// `dart_openai`'s own request and response handling is in the path.
//
// The two invariants that matter beyond the notice: no `StreamCompleted` /
// `ConnectorOk` carrying the garbled text reaches the caller, and the turn
// leaves no history behind — the one automatic re-send has to go out against
// the history the refused call saw.

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_openai.dart';

/// The reply from #147: normal Dutch with one word replaced by a clump of
/// non-Latin lookalikes.
const String _garbled =
    '<TEXT>Niet **աբգդե**: de voorwaarde wordt `True`, dus er wordt **ja** '
    'afgedrukt. De eerste helft wordt eerst `False` door de `not`, en daarna '
    'maakt `or` het geheel alsnog `True`.</TEXT>'
    '<META>{"type":"answer"}</META>';

const String _clean =
    '<TEXT>Niet **helemaal**: de voorwaarde wordt `True`, dus er wordt '
    '**ja** afgedrukt.</TEXT>'
    '<META>{"type":"answer"}</META>';

void main() {
  group('streamed', () {
    Future<List<StreamChunk>> collect(OpenaiConnector c, String reply) => c
        .assembleStream(
          Stream.fromIterable([reply]),
          input: 'vraag',
          inputs: PreviousInputs.includeSession,
        )
        .toList();

    test('a garbled reply fails instead of completing with the text it '
        'carried', () async {
      final c = OpenaiConnector();
      final chunks = await collect(c, _garbled);

      expect(chunks.whereType<StreamCompleted>(), isEmpty);
      final failed = chunks.last as StreamFailed;
      expect(failed.notice.kind, ChatNoticeKind.replyGarbled);
      expect(failed.error.toString(), contains('աբգդե'));
      expect(c.sessionHistory, isEmpty, reason: 'no history for a lost turn');
    });

    test('the same reply completes once the word is Dutch again', () async {
      final c = OpenaiConnector();
      final chunks = await collect(c, _clean);

      expect(chunks.last, isA<StreamCompleted>());
      expect(c.sessionHistory, hasLength(1));
    });

    test(
      'a reply split across chunks is judged whole, not per chunk',
      () async {
        // The run arrives in two deltas, so neither chunk holds it on its own.
        final c = OpenaiConnector();
        final chunks = await c
            .assembleStream(
              Stream.fromIterable([
                '<TEXT>Niet **աբ',
                'գդե**: de voorwaarde wordt waar, dus er wordt ja afgedrukt in '
                    'dit voorbeeld.</TEXT><META>{"type":"answer"}</META>',
              ]),
              input: 'vraag',
              inputs: PreviousInputs.includeSession,
            )
            .toList();

        expect(chunks.whereType<StreamCompleted>(), isEmpty);
        expect(
          (chunks.last as StreamFailed).notice.kind,
          ChatNoticeKind.replyGarbled,
        );
      },
    );
  });

  group('non-streamed', () {
    test(
      'a garbled grader reply is a failure the caller can re-send',
      () async {
        final openai = FakeOpenAi(text: _garbled);
        final c = OpenaiConnector(client: openai.client);

        final result = await c.sendRequest(instructions: 'sys', input: 'vraag');

        expect(result, isA<ConnectorFailure>());
        expect(
          (result as ConnectorFailure).notice.kind,
          ChatNoticeKind.replyGarbled,
        );
        expect(
          c.sessionHistory,
          isEmpty,
          reason: 'the re-send must see the history the refused call saw',
        );
      },
    );

    test('a clean grader reply is passed through', () async {
      final openai = FakeOpenAi(text: _clean);
      final c = OpenaiConnector(client: openai.client);

      final result = await c.sendRequest(instructions: 'sys', input: 'vraag');

      expect(result, isA<ConnectorOk>());
      expect((result as ConnectorOk).output, _clean);
      expect(c.sessionHistory, hasLength(1));
    });
  });
}
