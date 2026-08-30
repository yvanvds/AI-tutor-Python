import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/envelope_assembler.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/foundation.dart';

enum PreviousInputs { includeAll, includeSession, newSession }

sealed class ConnectorResult {
  const ConnectorResult();
}

class ConnectorOk extends ConnectorResult {
  /// Raw assistant text (chat.completions content). The parser handles both
  /// the envelope format and legacy JSON-only output.
  final String output;
  const ConnectorOk(this.output);
}

class ConnectorFailure extends ConnectorResult {
  final Object error;
  final StackTrace stack;

  /// Student-facing description, localized by the chat widget (#23).
  final ChatNotice notice;
  const ConnectorFailure(this.error, this.stack, this.notice);
}

/// Streaming events emitted by [OpenaiConnector.sendRequestStream].
sealed class StreamChunk {
  const StreamChunk();
}

/// Visible text appended to the student-facing message.
class StreamTextDelta extends StreamChunk {
  final String text;
  const StreamTextDelta(this.text);
}

/// The stream finished and produced a parsed response.
class StreamCompleted extends StreamChunk {
  final ChatResponse response;
  const StreamCompleted(this.response);
}

/// Transport or parse failure.
class StreamFailed extends StreamChunk {
  final Object error;
  final StackTrace stack;

  /// Student-facing description, localized by the chat widget (#23).
  final ChatNotice notice;
  const StreamFailed(this.error, this.stack, this.notice);
}

class OpenaiConnector {
  OpenaiConnector({
    void Function(String)? onRecordRawOutput,
    void Function(String)? onRecordStreamFailure,
    GlobalConfig? Function()? getConfig,
  })  : _onRecordRawOutput = onRecordRawOutput,
        _onRecordStreamFailure = onRecordStreamFailure,
        _getConfig = getConfig;

  final void Function(String)? _onRecordRawOutput;
  final void Function(String)? _onRecordStreamFailure;
  final GlobalConfig? Function()? _getConfig;

  final String _apiKey = Env.apiKey;

  /// Reasoning effort for gpt-5 / o-series models.
  /// One of: 'minimal' | 'low' | 'medium' | 'high', or null to omit the
  /// field entirely (use the model's default, or for non-reasoning models).
  /// Edit in source while tuning; promote to GlobalConfig once the right
  /// value is known.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? reasoningEffort = 'low';

  /// Hard cap on each history scope. Keeps memory bounded and trims input
  /// tokens for long-lived sessions.
  static const int _maxHistoryEntries = 50;

  // for resend
  String? _previousInstructions;
  String? _previousInput;
  PreviousInputs _previousScope = PreviousInputs.includeSession;

  // Full history (spans sessions) and current-session history.
  // Each entry is `{role: user|assistant, content: ...}`.
  final List<Map<String, String>> _allHistory = [];
  final List<Map<String, String>> _sessionHistory = [];

  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    debugPrint('system prompt: ${instructions.length} chars');
    _rememberForResend(instructions, input, inputs);
    OpenAI.apiKey = _apiKey;
    OpenAI.requestsTimeOut = const Duration(seconds: 60);

    if (inputs == PreviousInputs.newSession) {
      _sessionHistory.clear();
    }

    final messages = _buildMessages(instructions, _historyFor(inputs), input);

    try {
      final model = _resolveModel();
      final response = await OpenAI.instance.chat.create(
        model: model,
        messages: messages,
        extraParams: _extraParams(model),
      );
      _recordUserTurn(input, inputs);
      final text = _extractText(response);
      _onRecordRawOutput?.call(text);
      return ConnectorOk(text);
    } catch (e, stack) {
      debugPrint('OpenaiConnector.sendRequest failed: $e');
      return ConnectorFailure(e, stack, describeTransportError(e));
    }
  }

  /// Streaming variant. Emits [StreamTextDelta]s as visible text arrives,
  /// then a single [StreamCompleted] (or [StreamFailed]). The connector
  /// records history once on success so a failed stream does not poison it.
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    debugPrint('system prompt: ${instructions.length} chars');
    _rememberForResend(instructions, input, inputs);
    OpenAI.apiKey = _apiKey;
    OpenAI.requestsTimeOut = const Duration(seconds: 60);

    if (inputs == PreviousInputs.newSession) {
      _sessionHistory.clear();
    }

    final messages = _buildMessages(instructions, _historyFor(inputs), input);

    // Opening the stream is deferred into the generator so a synchronous
    // throw from `createStream` (bad key, bad model) lands in the same
    // StreamFailed path as a mid-stream transport error.
    Stream<String> deltas() async* {
      final model = _resolveModel();
      final stream = OpenAI.instance.chat.createStream(
        model: model,
        messages: messages,
        extraParams: _extraParams(model),
      );
      await for (final event in stream) {
        if (event.choices.isEmpty) continue;
        final delta = event.choices.first.delta;
        final content = delta.content;
        if (content == null) continue;
        for (final item in content) {
          final t = item?.text;
          if (t == null || t.isEmpty) continue;
          yield t;
        }
      }
    }

    return assembleStream(deltas(), input: input, inputs: inputs);
  }

  /// Longest gap tolerated between two streamed chunks. `OpenAI.requestsTimeOut`
  /// only bounds opening the connection; a stream that stalls after the
  /// first token would otherwise hang the tutor forever (#7).
  static const Duration streamIdleTimeout = Duration(seconds: 45);

  /// Turns raw text deltas into [StreamChunk]s: incremental envelope
  /// parsing, idle-timeout, truncation detection, history recording. Split
  /// from [sendRequestStream] so the failure paths can be tested without
  /// an OpenAI socket.
  @visibleForTesting
  Stream<StreamChunk> assembleStream(
    Stream<String> textDeltas, {
    required String input,
    required PreviousInputs inputs,
    Duration idleTimeout = streamIdleTimeout,
  }) async* {
    final assembler = EnvelopeAssembler();
    final raw = StringBuffer();

    try {
      await for (final t in textDeltas.timeout(idleTimeout)) {
        raw.write(t);
        final visible = assembler.add(t);
        if (visible.isNotEmpty) yield StreamTextDelta(visible);
      }

      final tail = assembler.close();
      if (tail.isNotEmpty) yield StreamTextDelta(tail);

      _onRecordRawOutput?.call(raw.toString());

      // The stream ended cleanly but the envelope never closed: the reply
      // was cut off in transit (proxy reset, model stopped mid-token).
      // Treat it like a transport failure — the partial text is not a
      // usable answer and the caller's retry gets a fresh, complete one.
      if (assembler.sawOpenTag && !assembler.sawCloseMeta) {
        debugPrint('OpenaiConnector: stream truncated before </META>');
        _onRecordStreamFailure?.call('truncated: ${raw.length} chars');
        yield StreamFailed(
          StateError('stream ended before </META>'),
          StackTrace.current,
          const ChatNotice(ChatNoticeKind.replyTruncated),
        );
        return;
      }

      final ChatResponse parsed = assembler.sawOpenTag
          ? AIResponseParser.fromEnvelopePieces(
              assembler.text,
              assembler.metaRaw,
            )
          : AIResponseParser.parse(raw.toString());

      if (parsed is! ErrorResponse) {
        _recordUserTurn(input, inputs);
      }
      yield StreamCompleted(parsed);
    } catch (e, stack) {
      debugPrint('OpenaiConnector.sendRequestStream failed: $e');
      _onRecordStreamFailure?.call(e.toString());
      yield StreamFailed(e, stack, describeTransportError(e));
    }
  }

  /// Student-facing one-liner for a transport failure. The raw exception
  /// (`SocketException: Failed host lookup ...`) stays in the debug log;
  /// unknown errors are passed through verbatim.
  static ChatNotice describeTransportError(Object e) {
    if (e is TimeoutException) {
      return const ChatNotice(ChatNoticeKind.tutorTimeout);
    }
    if (e is SocketException || e is HttpException) {
      return const ChatNotice(ChatNoticeKind.tutorUnreachable);
    }
    return ChatNotice.raw(e.toString());
  }

  Future<ConnectorResult> resendRequest() async {
    final prevInstructions = _previousInstructions;
    final prevInput = _previousInput;
    if (prevInstructions == null || prevInput == null) {
      return ConnectorFailure(
        StateError('No previous request to resend'),
        StackTrace.current,
        const ChatNotice(ChatNoticeKind.noPreviousRequest),
      );
    }
    return sendRequest(
      instructions: prevInstructions,
      input: prevInput,
      inputs: _previousScope,
    );
  }

  Stream<StreamChunk> resendRequestStream() async* {
    final prevInstructions = _previousInstructions;
    final prevInput = _previousInput;
    if (prevInstructions == null || prevInput == null) {
      yield StreamFailed(
        StateError('No previous request to resend'),
        StackTrace.current,
        const ChatNotice(ChatNoticeKind.noPreviousRequest),
      );
      return;
    }
    yield* sendRequestStream(
      instructions: prevInstructions,
      input: prevInput,
      inputs: _previousScope,
    );
  }

  /// Record the assistant turn into history (skip errors).
  void addResponse(ChatResponse response) {
    if (response is ErrorResponse) return;
    final jsonString = jsonEncode(response.toJson());
    _allHistory.add({'role': 'assistant', 'content': jsonString});
    _sessionHistory.add({'role': 'assistant', 'content': jsonString});
    _trim(_allHistory);
    _trim(_sessionHistory);
  }

  /// If you need to manually start a fresh session boundary.
  void startNewSession() {
    _sessionHistory.clear();
  }

  // ---- Private helpers ------------------------------------------------------

  void _rememberForResend(
    String instructions,
    String input,
    PreviousInputs scope,
  ) {
    _previousInstructions = instructions;
    _previousInput = input;
    _previousScope = scope;
  }

  /// Extra body params merged into chat.completions calls. Currently only
  /// carries `reasoning_effort` for gpt-5 / o-series models. Returns null
  /// when there's nothing to add so the field is omitted entirely.
  Map<String, dynamic>? _extraParams(String model) {
    final params = <String, dynamic>{};
    final supportsReasoning =
        RegExp(r'^o\d|^gpt-5').hasMatch(model);
    if (reasoningEffort != null && supportsReasoning) {
      params['reasoning_effort'] = reasoningEffort;
    }
    return params.isEmpty ? null : params;
  }

  String _resolveModel() {
    final cfg = _getConfig?.call();
    final m = cfg?.model;
    final result = (m != null && m.isNotEmpty) ? m : 'gpt-4o';
    debugPrint('Resolved model: $result');
    return result;
  }

  List<OpenAIChatCompletionChoiceMessageModel> _buildMessages(
    String instructions,
    List<Map<String, String>> history,
    String userInput,
  ) {
    OpenAIChatCompletionChoiceMessageModel msg(
      OpenAIChatMessageRole role,
      String text,
    ) => OpenAIChatCompletionChoiceMessageModel(
      role: role,
      content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(text)],
    );

    return [
      msg(OpenAIChatMessageRole.system, instructions),
      for (final h in history)
        msg(
          h['role'] == 'assistant'
              ? OpenAIChatMessageRole.assistant
              : OpenAIChatMessageRole.user,
          h['content'] ?? '',
        ),
      msg(OpenAIChatMessageRole.user, userInput),
    ];
  }

  String _extractText(OpenAIChatCompletionModel response) {
    if (response.choices.isEmpty) return '';
    final content = response.choices.first.message.content;
    if (content == null || content.isEmpty) return '';
    return content.map((c) => c.text ?? '').join();
  }

  void _recordUserTurn(String input, PreviousInputs inputs) {
    if (inputs != PreviousInputs.newSession) {
      _sessionHistory.add({'role': 'user', 'content': input});
      _trim(_sessionHistory);
    }
    _allHistory.add({'role': 'user', 'content': input});
    _trim(_allHistory);
  }

  void _trim(List<Map<String, String>> list) {
    if (list.length > _maxHistoryEntries) {
      list.removeRange(0, list.length - _maxHistoryEntries);
    }
  }

  List<Map<String, String>> _historyFor(PreviousInputs scope) {
    switch (scope) {
      case PreviousInputs.includeAll:
        return List<Map<String, String>>.from(_allHistory);
      case PreviousInputs.includeSession:
        return List<Map<String, String>>.from(_sessionHistory);
      case PreviousInputs.newSession:
        return const <Map<String, String>>[];
    }
  }

  /// For debugging/inspection.
  List<Map<String, String>> get allHistory => List.unmodifiable(_allHistory);
  List<Map<String, String>> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
}
