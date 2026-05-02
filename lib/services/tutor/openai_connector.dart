import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/services/data_service.dart';
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
  final String message;
  const ConnectorFailure(this.error, this.stack, this.message);
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
  final String message;
  const StreamFailed(this.error, this.stack, this.message);
}

class OpenaiConnector {
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
      final response = await OpenAI.instance.chat.create(
        model: _resolveModel(),
        messages: messages,
        extraParams: _extraParams(),
      );
      _recordUserTurn(input, inputs);
      return ConnectorOk(_extractText(response));
    } catch (e, stack) {
      debugPrint('OpenaiConnector.sendRequest failed: $e');
      return ConnectorFailure(e, stack, e.toString());
    }
  }

  /// Streaming variant. Emits [StreamTextDelta]s as visible text arrives,
  /// then a single [StreamCompleted] (or [StreamFailed]). The connector
  /// records history once on success so a failed stream does not poison it.
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async* {
    debugPrint('system prompt: ${instructions.length} chars');
    _rememberForResend(instructions, input, inputs);
    OpenAI.apiKey = _apiKey;
    OpenAI.requestsTimeOut = const Duration(seconds: 60);

    if (inputs == PreviousInputs.newSession) {
      _sessionHistory.clear();
    }

    final messages = _buildMessages(instructions, _historyFor(inputs), input);
    final assembler = EnvelopeAssembler();
    final raw = StringBuffer();

    try {
      final stream = OpenAI.instance.chat.createStream(
        model: _resolveModel(),
        messages: messages,
        extraParams: _extraParams(),
      );

      await for (final event in stream) {
        if (event.choices.isEmpty) continue;
        final delta = event.choices.first.delta;
        final content = delta.content;
        if (content == null) continue;
        for (final item in content) {
          final t = item?.text;
          if (t == null || t.isEmpty) continue;
          raw.write(t);
          final visible = assembler.add(t);
          if (visible.isNotEmpty) yield StreamTextDelta(visible);
        }
      }

      final tail = assembler.close();
      if (tail.isNotEmpty) yield StreamTextDelta(tail);

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
      yield StreamFailed(e, stack, e.toString());
    }
  }

  Future<ConnectorResult> resendRequest() async {
    final prevInstructions = _previousInstructions;
    final prevInput = _previousInput;
    if (prevInstructions == null || prevInput == null) {
      return ConnectorFailure(
        StateError('No previous request to resend'),
        StackTrace.current,
        'Geen vorige aanvraag om opnieuw te proberen.',
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
        'Geen vorige aanvraag om opnieuw te proberen.',
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
  Map<String, dynamic>? _extraParams() {
    final params = <String, dynamic>{};
    if (reasoningEffort != null) {
      params['reasoning_effort'] = reasoningEffort;
    }
    return params.isEmpty ? null : params;
  }

  String _resolveModel() {
    final cfg = DataService.globalConfig.cachedConfig;
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
