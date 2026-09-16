// Issue #125 — `OpenaiConnector.probe`, the call behind the Test button in
// Options, driven over a scripted HTTP client (no OpenAI socket):
//
//   - it is one chat completion with the one probe prompt and nothing else:
//     no system prompt, no history, no `max_tokens`;
//   - it carries the same `reasoning_effort` the real calls add for the
//     gpt-5 / o-series, and nothing for the others — so a parameter the
//     model rejects fails the test, not a student's first question;
//   - it records nothing: a probe is not a turn;
//   - a request the API refuses comes back as `ModelProbeFailed` carrying
//     the API's own message, a transport failure as the localized notice —
//     and neither is thrown.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A chat completion answering "OK", in the shape `dart_openai` parses.
String _okCompletion() => jsonEncode({
  'id': 'chatcmpl-probe',
  'object': 'chat.completion',
  'created': 1700000000,
  'model': 'gpt-5-mini',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': 'OK'},
      'finish_reason': 'stop',
    },
  ],
  'usage': {'prompt_tokens': 9, 'completion_tokens': 1, 'total_tokens': 10},
});

/// OpenAI's error envelope.
String _apiError(String message, {String type = 'invalid_request_error'}) =>
    jsonEncode({
      'error': {'message': message, 'type': type, 'param': null, 'code': null},
    });

void main() {
  late List<http.Request> requests;

  setUp(() {
    requests = [];
  });

  /// A connector whose every request lands in [requests] and is answered by
  /// [respond].
  OpenaiConnector connector(http.Response Function(http.Request) respond) =>
      OpenaiConnector(
        client: MockClient((req) async {
          requests.add(req);
          return respond(req);
        }),
      );

  Map<String, dynamic> bodyOf(http.Request req) =>
      jsonDecode(req.body) as Map<String, dynamic>;

  test(
    'a model that answers is reported ok, with the round-trip time',
    () async {
      final c = connector((_) => http.Response(_okCompletion(), 200));

      final result = await c.probe('gpt-5-mini');

      expect(result, isA<ModelProbeOk>());
      final ok = result as ModelProbeOk;
      expect(ok.model, 'gpt-5-mini');
      expect(ok.latency.isNegative, isFalse);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/chat/completions'));
    },
  );

  test('the request is one user message with the probe prompt and no '
      'system prompt, history or max_tokens', () async {
    final c = connector((_) => http.Response(_okCompletion(), 200));

    await c.probe('gpt-4.1');

    final body = bodyOf(requests.single);
    expect(body['model'], 'gpt-4.1');
    final messages = body['messages'] as List;
    expect(messages, hasLength(1));
    expect(messages.single['role'], 'user');
    expect(
      jsonEncode(messages.single['content']),
      contains(OpenaiConnector.probePrompt),
    );
    expect(body.containsKey('max_tokens'), isFalse);
    expect(body.containsKey('max_completion_tokens'), isFalse);
  });

  test('reasoning_effort goes out for the gpt-5 and o-series families, '
      'exactly as the tutor sends it', () async {
    for (final model in ['gpt-5-mini', 'gpt-5', 'o4-mini', 'o3']) {
      requests.clear();
      final c = connector((_) => http.Response(_okCompletion(), 200));
      await c.probe(model);
      expect(
        bodyOf(requests.single)['reasoning_effort'],
        OpenaiConnector.reasoningEffort,
        reason: model,
      );
    }
  });

  test('and not for the models that do not take it', () async {
    for (final model in ['gpt-4.1', 'gpt-4o-mini', 'gpt-4o']) {
      requests.clear();
      final c = connector((_) => http.Response(_okCompletion(), 200));
      await c.probe(model);
      expect(
        bodyOf(requests.single).containsKey('reasoning_effort'),
        isFalse,
        reason: model,
      );
    }
  });

  test('a probe records nothing in either history', () async {
    final c = connector((_) => http.Response(_okCompletion(), 200));

    await c.probe('gpt-5-mini');
    await c.probe('gpt-4.1');

    expect(c.allHistory, isEmpty);
    expect(c.sessionHistory, isEmpty);
    // And leaves nothing to resend.
    final resend = await c.resendRequest();
    expect(resend, isA<ConnectorFailure>());
    expect(
      (resend as ConnectorFailure).notice.kind,
      ChatNoticeKind.noPreviousRequest,
    );
  });

  test("a request the API refuses fails with the API's own message", () async {
    const message =
        'The model `gpt-6-ultra` does not exist or you do not have access '
        'to it.';
    final c = connector(
      (_) => http.Response(_apiError(message), 404, headers: const {}),
    );

    final result = await c.probe('gpt-6-ultra');

    expect(result, isA<ModelProbeFailed>());
    final failed = result as ModelProbeFailed;
    expect(failed.reason.kind, ChatNoticeKind.raw);
    expect(failed.reason.args, [message]);
    expect(failed.error.toString(), contains('404'));
  });

  test('an unsupported parameter is reported in the same way', () async {
    const message =
        "Unsupported parameter: 'reasoning_effort' is not supported with "
        'this model.';
    final c = connector((_) => http.Response(_apiError(message), 400));

    final result = await c.probe('gpt-5-chat-latest');

    expect((result as ModelProbeFailed).reason, ChatNotice.raw(message));
  });

  test('a quota problem is reported in the same way', () async {
    const message =
        'You exceeded your current quota, please check your plan and '
        'billing details.';
    final c = connector(
      (_) => http.Response(_apiError(message, type: 'insufficient_quota'), 429),
    );

    final result = await c.probe('gpt-4.1');

    expect((result as ModelProbeFailed).reason, ChatNotice.raw(message));
  });

  test('a refused key is reported against whoever owns it, not with the '
      "API's line (#126)", () async {
    const message =
        'Incorrect API key provided: sk-abc***. You can find '
        'your API key at https://platform.openai.com/account/api-keys.';
    http.Response refuse(http.Request _) =>
        http.Response(_apiError(message, type: 'invalid_request_error'), 401);

    // Without a key seam the probe runs on the school's build-time key.
    final school = await connector(refuse).probe('gpt-4.1');
    expect(
      (school as ModelProbeFailed).reason,
      const ChatNotice(ChatNoticeKind.schoolKeyInvalid),
    );

    final own = await OpenaiConnector(
      getApiKey: () => const OwnKey('sk-own'),
      client: MockClient((req) async => refuse(req)),
    ).probe('gpt-4.1');
    expect(
      (own as ModelProbeFailed).reason,
      const ChatNotice(ChatNoticeKind.ownKeyRejected),
    );
  });

  test('a dead connection is the localized transport notice, and a timeout '
      'the other one', () async {
    final unreachable = connector(
      (_) => throw const SocketException('Failed host lookup'),
    );
    final r1 = await unreachable.probe('gpt-4.1');
    expect(
      (r1 as ModelProbeFailed).reason.kind,
      ChatNoticeKind.tutorUnreachable,
    );

    final stalled = connector((_) => throw TimeoutException('60 s'));
    final r2 = await stalled.probe('gpt-4.1');
    expect((r2 as ModelProbeFailed).reason.kind, ChatNoticeKind.tutorTimeout);
  });
}
