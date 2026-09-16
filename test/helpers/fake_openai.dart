import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// OpenAI's `chat.completions` endpoint as a scripted `http.Client` (#126).
///
/// Handed to the *real* `OpenaiConnector` through its `client` seam, so a
/// test drives the production request path — `dart_openai`'s headers, body
/// and response parsing included — and reads back what actually went on
/// the wire. [requests] keeps every request; [bearers] is the key each one
/// carried, which is what #126 is about.
///
/// [answer] decides the response. The default answers every request with
/// [text], in whichever shape the request asked for: one SSE stream for a
/// `stream: true` body (the tutor's question turns), a plain completion
/// otherwise (the grader, the status report, the Test button).
class FakeOpenAi {
  FakeOpenAi({this.text = 'OK'});

  /// The assistant text a default [answer] replies with.
  String text;

  /// Every request the app made, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The `Authorization` header of every request, in order.
  List<String?> get bearers =>
      requests.map((r) => r.headers['Authorization']).toList(growable: false);

  /// What a request is answered with. Reassign to script a refusal
  /// ([unauthorized], [apiError]) or a transport failure (throw).
  late http.Response Function(http.Request request) answer = (req) =>
      http.Response(
        wantsStream(req) ? streamed(text) : completion(text),
        200,
        headers: const {'content-type': 'application/json'},
      );

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    return answer(req);
  });

  /// Whether [req] asked for server-sent events.
  static bool wantsStream(http.Request req) {
    try {
      return (jsonDecode(req.body) as Map<String, dynamic>)['stream'] == true;
    } on FormatException {
      return false;
    }
  }

  /// A finished chat completion carrying [content], in the shape
  /// `dart_openai` parses.
  static String completion(String content) => jsonEncode({
    'id': 'chatcmpl-fake',
    'object': 'chat.completion',
    'created': 1700000000,
    'model': 'gpt-4o',
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': content},
        'finish_reason': 'stop',
      },
    ],
    'usage': {'prompt_tokens': 9, 'completion_tokens': 1, 'total_tokens': 10},
  });

  /// The same reply as one SSE chunk followed by the terminator — what a
  /// `stream: true` request gets back.
  static String streamed(String content) {
    final chunk = jsonEncode({
      'id': 'chatcmpl-fake',
      'object': 'chat.completion.chunk',
      'created': 1700000000,
      'model': 'gpt-4o',
      'choices': [
        {
          'index': 0,
          'delta': {'role': 'assistant', 'content': content},
          'finish_reason': null,
        },
      ],
    });
    return 'data: $chunk\n\ndata: [DONE]\n\n';
  }

  /// OpenAI's error envelope with [status].
  static http.Response apiError(
    String message, {
    required int status,
    String type = 'invalid_request_error',
    String? code,
  }) => http.Response(
    jsonEncode({
      'error': {'message': message, 'type': type, 'param': null, 'code': code},
    }),
    status,
    headers: const {'content-type': 'application/json'},
  );

  /// What OpenAI answers to a key it does not accept.
  static http.Response unauthorized() => apiError(
    'Incorrect API key provided: sk-abc***. You can find your API key at '
    'https://platform.openai.com/account/api-keys.',
    status: 401,
    code: 'invalid_api_key',
  );
}
