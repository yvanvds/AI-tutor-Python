// Issue #183 — the connector reads what each call cost.
//
// Every chat.completions response carries a `usage` block; the connector
// used to drop it. `dart_openai` parses `usage` into models without
// `prompt_tokens_details`, so the cached share of the input is read off the
// raw response on its way to the package. A streamed call asks for the
// usage chunk (`stream_options.include_usage`) and reads it off the stream's
// last chunk.
//
// The wire-level tests drive the real connector — `dart_openai`'s request
// and response handling included — over a scripted HTTP client.

import 'dart:convert';

import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_openai.dart';

const _reply = '<TEXT>Hallo</TEXT><META>{"type":"answer"}</META>';

void main() {
  group('usageInResponseBody', () {
    test('a completion: the top-level block, cached share included', () {
      final body = FakeOpenAi.completion(
        _reply,
        usage: FakeOpenAi.usageBlock(
          prompt: 2006,
          completion: 300,
          cached: 1920,
        ),
      );
      expect(
        usageInResponseBody(body),
        const TokenUsage(
          promptTokens: 2006,
          cachedTokens: 1920,
          completionTokens: 300,
        ),
      );
    });

    test('a completion without prompt_tokens_details: nothing cached', () {
      expect(
        usageInResponseBody(FakeOpenAi.completion(_reply)),
        const TokenUsage(promptTokens: 9, completionTokens: 1),
      );
    });

    test('a pretty-printed completion reads the same', () {
      final body = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(FakeOpenAi.completion(_reply)));
      expect(
        usageInResponseBody(body),
        const TokenUsage(promptTokens: 9, completionTokens: 1),
      );
    });

    test('a stream: the last chunk, past the `usage: null` of the others', () {
      final body = FakeOpenAi.streamed(
        _reply,
        usage: FakeOpenAi.usageBlock(prompt: 800, completion: 120, cached: 512),
      );
      expect(
        usageInResponseBody(body),
        const TokenUsage(
          promptTokens: 800,
          cachedTokens: 512,
          completionTokens: 120,
        ),
      );
    });

    test('a stream that did not ask, an error, garbage: nothing', () {
      expect(usageInResponseBody(FakeOpenAi.streamed(_reply)), isNull);
      expect(usageInResponseBody(FakeOpenAi.unauthorized().body), isNull);
      expect(usageInResponseBody('{not json'), isNull);
      expect(usageInResponseBody(''), isNull);
    });
  });

  group('on the wire', () {
    late FakeOpenAi openai;

    OpenaiConnector connector() => OpenaiConnector(
      getApiKey: () => const SchoolKey('sk-test'),
      getModelOverride: () => 'gpt-5-mini',
      client: openai.client,
    );

    Map<String, dynamic> body(int i) =>
        jsonDecode(openai.requests[i].body) as Map<String, dynamic>;

    setUp(() {
      openai = FakeOpenAi(
        text: _reply,
        usage: FakeOpenAi.usageBlock(
          prompt: 1500,
          completion: 300,
          cached: 1024,
        ),
      );
    });

    const expected = CallUsage(
      model: 'gpt-5-mini',
      tokens: TokenUsage(
        promptTokens: 1500,
        cachedTokens: 1024,
        completionTokens: 300,
      ),
    );

    test('a non-streamed call comes back with what it cost', () async {
      final result = await connector().sendRequest(
        instructions: 'sys',
        input: 'vraag',
      );
      expect(result, isA<ConnectorOk>());
      expect((result as ConnectorOk).usage, expected);
    });

    test('a completion without prompt_tokens_details counts nothing as '
        'cached', () async {
      openai.usage = FakeOpenAi.usageBlock(prompt: 700, completion: 90);
      final result = await connector().sendRequest(
        instructions: 'sys',
        input: 'vraag',
      ) as ConnectorOk;
      expect(
        result.usage?.tokens,
        const TokenUsage(promptTokens: 700, completionTokens: 90),
      );
    });

    test('a streamed call asks for the usage chunk and completes with '
        'it', () async {
      final chunks = await connector()
          .sendRequestStream(instructions: 'sys', input: 'vraag')
          .toList();

      expect(body(0)['stream'], isTrue);
      expect(body(0)['stream_options'], {'include_usage': true});
      final done = chunks.last;
      expect(done, isA<StreamCompleted>());
      expect((done as StreamCompleted).usage, expected);
      expect(
        chunks.whereType<StreamTextDelta>().map((d) => d.text).join(),
        'Hallo',
        reason: 'the usage chunk carries no text',
      );
    });

    test('a stream that carries no usage completes without it', () async {
      openai.answer = (req) => http.Response(
        FakeOpenAi.streamed(_reply),
        200,
        headers: const {'content-type': 'application/json'},
      );
      final chunks = await connector()
          .sendRequestStream(instructions: 'sys', input: 'vraag')
          .toList();
      final done = chunks.last as StreamCompleted;
      expect(done.usage, isNull);
    });

    test('a reply the connector refuses still reports what it cost', () async {
      // A clump of non-Latin lookalikes in Dutch prose: the off-script
      // refusal (#147).
      openai.text =
          '<TEXT>Niet **աբգդե**: de voorwaarde wordt `True`, dus er wordt '
          '**ja** afgedrukt. De eerste helft wordt eerst `False` door de '
          '`not`, en daarna maakt `or` het geheel alsnog `True`.</TEXT>'
          '<META>{"type":"answer"}</META>';

      final result = await connector().sendRequest(
        instructions: 'sys',
        input: 'vraag',
      );
      expect(result, isA<ConnectorFailure>());
      final failure = result as ConnectorFailure;
      expect(failure.notice, const ChatNotice(ChatNoticeKind.replyGarbled));
      expect(failure.usage, expected);

      final chunks = await connector()
          .sendRequestStream(instructions: 'sys', input: 'vraag')
          .toList();
      final failed = chunks.last as StreamFailed;
      expect(failed.notice, const ChatNotice(ChatNoticeKind.replyGarbled));
      expect(failed.usage, expected);
    });

    test('a refused request costs nothing on record', () async {
      openai.answer = (_) => FakeOpenAi.unauthorized();
      final result = await connector().sendRequest(
        instructions: 'sys',
        input: 'vraag',
      );
      expect((result as ConnectorFailure).usage, isNull);
    });
  });
}
