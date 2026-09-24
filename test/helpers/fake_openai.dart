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
/// otherwise (the grader, the status report, the Test button). Like
/// OpenAI, it puts [usage] on a completion, and on a stream only when the
/// request asked for it (`stream_options.include_usage`, #183).
class FakeOpenAi {
  FakeOpenAi({this.text = 'OK', this.usage = defaultUsage});

  /// The assistant text a default [answer] replies with.
  String text;

  /// The `usage` block a default [answer] reports (#183).
  Map<String, dynamic> usage;

  /// What a reply reports when a test does not say.
  static const Map<String, dynamic> defaultUsage = {
    'prompt_tokens': 9,
    'completion_tokens': 1,
    'total_tokens': 10,
  };

  /// Every request the app made, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The `Authorization` header of every request, in order.
  List<String?> get bearers =>
      requests.map((r) => r.headers['Authorization']).toList(growable: false);

  /// What a request is answered with. Reassign to script a refusal
  /// ([unauthorized], [apiError]) or a transport failure (throw).
  late http.Response Function(http.Request request) answer = (req) =>
      reply(req, text, usage: usage);

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    return answer(req);
  });

  /// [content] in whichever shape [req] asked for, reporting [usage] where
  /// OpenAI would: always on a completion, on a stream only when asked.
  static http.Response reply(
    http.Request req,
    String content, {
    Map<String, dynamic> usage = defaultUsage,
  }) => http.Response(
    wantsStream(req)
        ? streamed(content, usage: wantsUsage(req) ? usage : null)
        : completion(content, usage: usage),
    200,
    headers: const {'content-type': 'application/json'},
  );

  /// OpenAI's `usage` block (#183). [cached] adds the
  /// `prompt_tokens_details` a response of a cached prompt carries.
  static Map<String, dynamic> usageBlock({
    required int prompt,
    required int completion,
    int? cached,
  }) => {
    'prompt_tokens': prompt,
    'completion_tokens': completion,
    'total_tokens': prompt + completion,
    if (cached != null)
      'prompt_tokens_details': {'cached_tokens': cached, 'audio_tokens': 0},
    'completion_tokens_details': {'reasoning_tokens': 0},
  };

  static Map<String, dynamic>? _body(http.Request req) {
    try {
      final decoded = jsonDecode(req.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether [req] asked for server-sent events.
  static bool wantsStream(http.Request req) => _body(req)?['stream'] == true;

  /// Whether [req] asked for the usage chunk at the end of its stream.
  static bool wantsUsage(http.Request req) {
    final options = _body(req)?['stream_options'];
    return options is Map && options['include_usage'] == true;
  }

  /// A finished chat completion carrying [content], in the shape
  /// `dart_openai` parses.
  static String completion(
    String content, {
    Map<String, dynamic> usage = defaultUsage,
  }) => jsonEncode({
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
    'usage': usage,
  });

  /// The same reply as one SSE chunk followed by the terminator — what a
  /// `stream: true` request gets back. With [usage], the chunk OpenAI sends
  /// last for a stream that asked for it goes in front of the terminator:
  /// no choices, the call's usage.
  static String streamed(String content, {Map<String, dynamic>? usage}) {
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
      if (usage != null) 'usage': null,
    });
    final usageChunk = usage == null
        ? ''
        : 'data: ${jsonEncode({'id': 'chatcmpl-fake', 'object': 'chat.completion.chunk', 'created': 1700000000, 'model': 'gpt-4o', 'choices': const <Object>[], 'usage': usage})}\n\n';
    return 'data: $chunk\n\n${usageChunk}data: [DONE]\n\n';
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
