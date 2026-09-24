import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/responses/ai_response_parser.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/envelope_assembler.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/script_guard.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// How much of the conversation a call carries in front of its input.
enum PreviousInputs {
  /// Every recorded turn, across sessions (capped). The status report.
  includeAll,

  /// Every turn since the session began: the last call on [newSession].
  includeSession,

  /// The current exercise's own exchange (#184): every turn since the
  /// exercise's question was asked. The question generation that opens an
  /// exercise goes out on [newSession], so its reply — the question itself
  /// — is the exercise's first entry. A grader, a hint or a follow-up sees
  /// that question and what was said about it since, and nothing of the
  /// exercises before. A question put in front of the student without a
  /// generation call has to open the exercise itself.
  exercise,

  /// No history at all. The call starts a new session, and with it a new
  /// exercise. Question generation: what was asked earlier reaches the
  /// model through the request's `recent_questions` block instead (#184).
  newSession,
}

sealed class ConnectorResult {
  const ConnectorResult();
}

class ConnectorOk extends ConnectorResult {
  /// Raw assistant text (chat.completions content). The parser handles both
  /// the envelope format and legacy JSON-only output.
  final String output;

  /// What the call cost (#183); `null` when the response carried no usage.
  final CallUsage? usage;
  const ConnectorOk(this.output, {this.usage});
}

class ConnectorFailure extends ConnectorResult {
  final Object error;
  final StackTrace stack;

  /// Student-facing description, localized by the chat widget (#23).
  final ChatNotice notice;

  /// What the call cost when a reply did come back but the connector
  /// refused it (#147); `null` when nothing came back.
  final CallUsage? usage;
  const ConnectorFailure(this.error, this.stack, this.notice, {this.usage});
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

  /// What the call cost (#183), from the stream's last chunk; `null` when
  /// the stream carried no usage.
  final CallUsage? usage;
  const StreamCompleted(this.response, {this.usage});
}

/// Transport or parse failure.
class StreamFailed extends StreamChunk {
  final Object error;
  final StackTrace stack;

  /// Student-facing description, localized by the chat widget (#23).
  final ChatNotice notice;

  /// What the call cost when the stream did finish but the connector
  /// refused the reply (#183); `null` when it broke off.
  final CallUsage? usage;
  const StreamFailed(this.error, this.stack, this.notice, {this.usage});
}

/// Outcome of [OpenaiConnector.probe] — the Test button in Options (#125).
sealed class ModelProbe {
  const ModelProbe();
}

/// The model answered a chat completion on this key.
class ModelProbeOk extends ModelProbe {
  final String model;

  /// Wall-clock time of the round trip, shown to the teacher as a hint of
  /// what a student will wait for.
  final Duration latency;
  const ModelProbeOk(this.model, this.latency);
}

/// The call did not come back with an answer. [reason] is what the teacher
/// is shown: OpenAI's own message for a request the API refused (an unknown
/// id, a parameter the model does not take, a quota problem), the localized
/// line naming whose key it is for a refused or missing key (#126), the
/// localized transport line for a timeout or a dead connection.
class ModelProbeFailed extends ModelProbe {
  final Object error;
  final StackTrace stack;
  final ChatNotice reason;
  const ModelProbeFailed(this.error, this.stack, this.reason);
}

/// Whose OpenAI key an account's calls go out on (#126).
///
/// Decided per account by `tutorApiKeyProvider` and handed to the connector
/// through its `getApiKey` seam. The connector keeps the *source* and not
/// just the string because a rejected key has to be reported to the right
/// person: the student who typed their own, or the teacher who owns the
/// school's.
sealed class ApiKeySource {
  const ApiKeySource();

  /// The key itself; `null` or empty when the source has none to offer.
  String? get key;
}

/// The school's key, bundled into the build: the account has
/// `mayUseGlobalKey`. A key the user may also have stored on the device is
/// ignored, consistent with the Options page hiding the own-key card for
/// such an account.
final class SchoolKey extends ApiKeySource {
  const SchoolKey(this.key);

  @override
  final String key;

  @override
  bool operator ==(Object other) => other is SchoolKey && other.key == key;

  @override
  int get hashCode => Object.hash(SchoolKey, key);

  @override
  String toString() => 'SchoolKey(${key.isEmpty ? 'empty' : 'set'})';
}

/// The key the user stored on this device (`LocalApiKeyStorage`): the
/// account does not have `mayUseGlobalKey`. `null` while there is none —
/// the local-key gate makes that unreachable in practice, but a call must
/// still fail rather than silently fall back on the school's key.
final class OwnKey extends ApiKeySource {
  const OwnKey(this.key);

  @override
  final String? key;

  @override
  bool operator ==(Object other) => other is OwnKey && other.key == key;

  @override
  int get hashCode => Object.hash(OwnKey, key);

  @override
  String toString() =>
      'OwnKey(${key == null || key!.isEmpty ? 'none' : 'set'})';
}

/// Thrown by [OpenaiConnector.resolveApiKey] when [source] has no key to
/// call with. Nothing is sent to OpenAI; the notice says whose key is
/// missing.
class NoApiKeyException implements Exception {
  const NoApiKeyException(this.source);
  final ApiKeySource source;

  @override
  String toString() => 'NoApiKeyException($source)';
}

class OpenaiConnector {
  OpenaiConnector({
    this._onRecordRawOutput,
    this._onRecordStreamFailure,
    this._getConfig,
    this._getModelOverride,
    this._getApiKey,
    this._client,
  });

  final void Function(String)? _onRecordRawOutput;
  final void Function(String)? _onRecordStreamFailure;
  final GlobalConfig? Function()? _getConfig;

  /// This device's model choice from the Options panel (#32), or `null` to
  /// follow the school-wide `GlobalConfig.Model`.
  final String? Function()? _getModelOverride;

  /// Whose key the next call goes out on (#126): the school's for an
  /// account with `mayUseGlobalKey`, the user's own otherwise — see
  /// `tutorApiKeyProvider`, which every production connector reads through
  /// this seam. `null` falls back on the school's build-time key, which is
  /// what the connector did unconditionally before #126; only tests and
  /// scripted stand-ins leave it unset.
  final ApiKeySource Function()? _getApiKey;

  /// The HTTP transport every call goes out on. `null` (production) lets
  /// `dart_openai` open its own connections with `OpenAI.requestsTimeOut`
  /// applied; a test passes a scripted client so a request can be inspected
  /// and answered without a socket (#125).
  final http.Client? _client;

  /// Reasoning effort for gpt-5 / o-series models.
  /// One of: 'minimal' | 'low' | 'medium' | 'high', or null to omit the
  /// field entirely (use the model's default, or for non-reasoning models).
  /// Edit in source while tuning; promote to GlobalConfig once the right
  /// value is known.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? reasoningEffort = 'low';

  /// Model used when neither this device nor the school-wide config names
  /// one — i.e. a `config/global` doc with an empty `Model` field.
  static const String defaultModel = 'gpt-4o';

  /// Hard cap on each history scope. Keeps memory bounded and trims input
  /// tokens for long-lived sessions.
  static const int _maxHistoryEntries = 50;

  // for resend
  String? _previousInstructions;
  String? _previousInput;
  PreviousInputs _previousScope = PreviousInputs.includeSession;

  // Full history (spans sessions), current-session history and the current
  // exercise's history (#184).
  // Each entry is `{role: user|assistant, content: ...}`.
  final List<Map<String, String>> _allHistory = [];
  final List<Map<String, String>> _sessionHistory = [];
  final List<Map<String, String>> _exerciseHistory = [];

  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    debugPrint('system prompt: ${instructions.length} chars');
    _rememberForResend(instructions, input, inputs);
    OpenAI.requestsTimeOut = const Duration(seconds: 60);

    final messages = _buildMessages(
      instructions,
      historyForCall(inputs),
      input,
    );

    final tap = _UsageTap(_client);
    try {
      // Inside the try on purpose: an account with no key to call with
      // fails the turn the same way a refused request does (#126).
      OpenAI.apiKey = resolveApiKey();
      final model = resolveModel();
      final response = await OpenAI.instance.chat
          .create(
            model: model,
            messages: messages,
            extraParams: _extraParams(model),
            client: tap,
          )
          // The package bounds a call only on a transport of its own; the
          // tap is the connector's, so the bound is the connector's too.
          .timeout(OpenAI.requestsTimeOut);
      final usage = tap.callUsage(model);
      final text = _extractText(response);
      _onRecordRawOutput?.call(text);

      // Refused before the user turn is on record, so the re-send goes out
      // against the same history the refused call saw (#147).
      final garbled = offScriptRunInReply(text);
      if (garbled != null) {
        debugPrint('OpenaiConnector: reply carries off-script run "$garbled"');
        return ConnectorFailure(
          StateError('reply carries an off-script run: $garbled'),
          StackTrace.current,
          const ChatNotice(ChatNoticeKind.replyGarbled),
          usage: usage,
        );
      }

      _recordUserTurn(input, inputs);
      return ConnectorOk(text, usage: usage);
    } catch (e, stack) {
      debugPrint('OpenaiConnector.sendRequest failed: $e');
      return ConnectorFailure(e, stack, _describeCallError(e));
    } finally {
      tap.close();
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
    OpenAI.requestsTimeOut = const Duration(seconds: 60);

    final messages = _buildMessages(
      instructions,
      historyForCall(inputs),
      input,
    );

    // Opening the stream is deferred into the generator so a synchronous
    // throw from `createStream` (bad key, bad model) — and an account with
    // no key at all (#126) — lands in the same StreamFailed path as a
    // mid-stream transport error.
    _UsageTap? tap;
    String? model;
    Stream<String> deltas() async* {
      final t = tap = _UsageTap(_client);
      try {
        OpenAI.apiKey = resolveApiKey();
        final m = model = resolveModel();
        final stream = OpenAI.instance.chat.createStream(
          model: m,
          messages: messages,
          // The stream's last chunk then carries the call's usage (#183).
          // Its `choices` is empty, so the loop below passes over it.
          streamOptions: const {'include_usage': true},
          extraParams: _extraParams(m),
          client: t,
        );
        await for (final event in stream) {
          if (event.choices.isEmpty) continue;
          final delta = event.choices.first.delta;
          final content = delta.content;
          if (content == null) continue;
          for (final item in content) {
            final text = item?.text;
            if (text == null || text.isEmpty) continue;
            yield text;
          }
        }
      } finally {
        t.close();
      }
    }

    return assembleStream(
      deltas(),
      input: input,
      inputs: inputs,
      usage: () {
        final m = model;
        return m == null ? null : tap?.callUsage(m);
      },
    );
  }

  /// Longest gap tolerated between two streamed chunks. `OpenAI.requestsTimeOut`
  /// only bounds opening the connection; a stream that stalls after the
  /// first token would otherwise hang the tutor forever (#7).
  static const Duration streamIdleTimeout = Duration(seconds: 45);

  /// Turns raw text deltas into [StreamChunk]s: incremental envelope
  /// parsing, idle-timeout, truncation detection, history recording. Split
  /// from [sendRequestStream] so the failure paths can be tested without
  /// an OpenAI socket.
  ///
  /// [usage] is asked once [textDeltas] is done, for what the call cost
  /// (#183): the stream's last chunk has been read by then.
  @visibleForTesting
  Stream<StreamChunk> assembleStream(
    Stream<String> textDeltas, {
    required String input,
    required PreviousInputs inputs,
    Duration idleTimeout = streamIdleTimeout,
    CallUsage? Function()? usage,
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
      final spent = usage?.call();

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
          usage: spent,
        );
        return;
      }

      // The prose came back with a run of characters from an alphabet the
      // tutor does not write in — a stray token out of a small model (#147).
      // Refused for the same reason a truncated reply is: it is not
      // something to leave in front of a student, and the caller's one
      // re-send normally comes back clean. The placeholder the deltas were
      // streaming into is dropped by `ChatService.failStream`, so the
      // garbled text does not survive the turn.
      final garbled = offScriptRunInReply(raw.toString());
      if (garbled != null) {
        debugPrint('OpenaiConnector: reply carries off-script run "$garbled"');
        _onRecordStreamFailure?.call('off-script run: $garbled');
        yield StreamFailed(
          StateError('reply carries an off-script run: $garbled'),
          StackTrace.current,
          const ChatNotice(ChatNoticeKind.replyGarbled),
          usage: spent,
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
      yield StreamCompleted(parsed, usage: spent);
    } catch (e, stack) {
      debugPrint('OpenaiConnector.sendRequestStream failed: $e');
      _onRecordStreamFailure?.call(e.toString());
      yield StreamFailed(e, stack, _describeCallError(e));
    }
  }

  /// Student-facing one-liner for a transport failure. The raw exception
  /// (`SocketException: Failed host lookup ...`) stays in the debug log;
  /// unknown errors are passed through verbatim.
  static ChatNotice describeTransportError(Object e) {
    if (e is NoApiKeyException) return _keyNotice(e.source, missing: true);
    if (e is TimeoutException) {
      return const ChatNotice(ChatNoticeKind.tutorTimeout);
    }
    if (e is SocketException || e is HttpException) {
      return const ChatNotice(ChatNoticeKind.tutorUnreachable);
    }
    return ChatNotice.raw(e.toString());
  }

  /// What a failed call of *this* connector reads as. On top of
  /// [describeTransportError]: a request OpenAI refused for its key (HTTP
  /// 401) is reported against whoever owns that key (#126) — the student's
  /// own, to be fixed under Options, or the school's, to be taken to the
  /// teacher — instead of the API's "Incorrect API key provided: sk-***"
  /// line, which points a student at a key that is not theirs to change.
  ChatNotice _describeCallError(Object e) {
    if (e is RequestFailedException &&
        e.statusCode == HttpStatus.unauthorized) {
      return _keyNotice(_apiKeySource(), missing: false);
    }
    return describeTransportError(e);
  }

  static ChatNotice _keyNotice(ApiKeySource source, {required bool missing}) =>
      switch (source) {
        OwnKey() => ChatNotice(
          missing
              ? ChatNoticeKind.ownKeyMissing
              : ChatNoticeKind.ownKeyRejected,
        ),
        // The school's key is nobody's to type in here: absent and refused
        // come to the same advice.
        SchoolKey() => const ChatNotice(ChatNoticeKind.schoolKeyInvalid),
      };

  /// Whether [notice] is one of the key problems [_keyNotice] reports: the
  /// account has no key to call with, or OpenAI refused the one it has.
  /// Re-sending such a turn as it is cannot help — the same key, or none,
  /// goes out again and the same refusal comes back — which is why the
  /// tutor's automatic retry skips it (#134); a timeout or a dropped socket
  /// may well go through the second time and is retried as before.
  static bool isKeyFailure(ChatNotice notice) => switch (notice.kind) {
    ChatNoticeKind.ownKeyMissing ||
    ChatNoticeKind.ownKeyRejected ||
    ChatNoticeKind.schoolKeyInvalid => true,
    _ => false,
  };

  /// The one user message the Test button sends (#125). Tiny on purpose: the
  /// point is the round trip, not the answer.
  static const String probePrompt = 'Reply with the single word OK.';

  /// Asks [model] for one chat completion on the tutor's key and reports
  /// whether it answered — the Test button in Options (#125).
  ///
  /// A real, minimal version of the call the tutor makes, not a
  /// `GET /v1/models/{id}`: that only says the id exists for this key, and
  /// `whisper-1` or an embedding model pass it while breaking the tutor.
  /// The same [_extraParams] the real calls add go out too, so a parameter
  /// the model rejects (`reasoning_effort` on a model that does not take it)
  /// surfaces here and not in a student's first question. No system prompt,
  /// no history, no envelope, and nothing is recorded: a probe is not a
  /// turn. No `max_tokens` either — the gpt-5 / o-series reject it in favour
  /// of `max_completion_tokens`.
  ///
  /// Never throws: every failure comes back as a [ModelProbeFailed] carrying
  /// what the teacher should read.
  Future<ModelProbe> probe(String model) async {
    OpenAI.requestsTimeOut = const Duration(seconds: 60);
    final clock = Stopwatch()..start();
    try {
      // The same key the tutor's calls go out on (#126), so on an own-key
      // account the Test button also validates the stored key.
      OpenAI.apiKey = resolveApiKey();
      await OpenAI.instance.chat.create(
        model: model,
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(
                probePrompt,
              ),
            ],
          ),
        ],
        extraParams: _extraParams(model),
        client: _client,
      );
      return ModelProbeOk(model, clock.elapsed);
    } catch (e, stack) {
      debugPrint('OpenaiConnector.probe($model) failed: $e');
      return ModelProbeFailed(e, stack, _describeProbeError(e));
    }
  }

  /// What the Test button shows for a failed probe. A request the API
  /// refused carries OpenAI's own explanation ("The model … does not
  /// exist", "Unsupported parameter: …"), which is exactly what the teacher
  /// needs to read; a key problem — refused or missing — gets the same line
  /// the chat shows for it (#126), and so does a transport failure.
  ChatNotice _describeProbeError(Object e) {
    if (e is RequestFailedException &&
        e.statusCode != HttpStatus.unauthorized) {
      return ChatNotice.raw(e.message);
    }
    return _describeCallError(e);
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
    for (final list in [_allHistory, _sessionHistory, _exerciseHistory]) {
      list.add({'role': 'assistant', 'content': jsonString});
      _trim(list);
    }
  }

  /// Records an exchange the app answered itself, without a call (#186): a
  /// multiple-choice pick on a bank question, graded from its answer key.
  /// It lands where the call it replaces would have left it — the user turn
  /// under [inputs], then the reply — so the history of the exercise, the
  /// session and a later status report reads the same either way.
  void addExchange({
    required String input,
    required ChatResponse response,
    PreviousInputs inputs = PreviousInputs.exercise,
  }) {
    _recordUserTurn(input, inputs);
    addResponse(response);
  }

  /// If you need to manually start a fresh session boundary. A new session
  /// starts a new exercise too. A question put in front of the student
  /// without a generation call — one from the question bank (#186) — opens
  /// its exercise with this, as the generation call would have.
  void startNewSession() {
    _sessionHistory.clear();
    _exerciseHistory.clear();
  }

  /// The history a call on [inputs] goes out with. A call on
  /// [PreviousInputs.newSession] starts over first: the session and the
  /// exercise both begin again with it (#184).
  ///
  /// Shared by both call shapes, and by stand-ins that replace the
  /// transport but keep the bookkeeping — the integration harness's
  /// `ScriptedLlm` records what each scripted call would have carried.
  @protected
  List<Map<String, String>> historyForCall(PreviousInputs inputs) {
    if (inputs == PreviousInputs.newSession) {
      _sessionHistory.clear();
      _exerciseHistory.clear();
    }
    return _historyFor(inputs);
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
    final supportsReasoning = RegExp(r'^o\d|^gpt-5').hasMatch(model);
    if (reasoningEffort != null && supportsReasoning) {
      params['reasoning_effort'] = reasoningEffort;
    }
    return params.isEmpty ? null : params;
  }

  /// Key the next call goes out on (#126): whatever the `getApiKey` seam
  /// says — the school's key for an account with `mayUseGlobalKey`, the
  /// user's own otherwise. Throws [NoApiKeyException] when that source has
  /// nothing to offer, so a call never quietly runs on a key the account is
  /// not entitled to. Without a seam, the school's build-time key.
  @visibleForTesting
  String resolveApiKey() {
    final source = _apiKeySource();
    final key = source.key;
    if (key == null || key.isEmpty) throw NoApiKeyException(source);
    return key;
  }

  ApiKeySource _apiKeySource() => _getApiKey?.call() ?? SchoolKey(Env.apiKey);

  /// Model the next call goes to: this device's override (#32) when the user
  /// picked one, else the school-wide `GlobalConfig.Model`, else the
  /// hard-coded fallback for a config doc that has never been filled in.
  @visibleForTesting
  String resolveModel() {
    final override = _getModelOverride?.call();
    if (override != null && override.isNotEmpty) {
      debugPrint('Resolved model (device override): $override');
      return override;
    }
    final cfg = _getConfig?.call();
    final m = cfg?.model;
    final result = (m != null && m.isNotEmpty) ? m : defaultModel;
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

  /// A call on [PreviousInputs.newSession] opens a session and an exercise
  /// with its *reply*: its own input (the question request) stays out of
  /// both, so an exercise starts with the question the model asked.
  void _recordUserTurn(String input, PreviousInputs inputs) {
    final lists = [
      _allHistory,
      if (inputs != PreviousInputs.newSession) ...[
        _sessionHistory,
        _exerciseHistory,
      ],
    ];
    for (final list in lists) {
      list.add({'role': 'user', 'content': input});
      _trim(list);
    }
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
      case PreviousInputs.exercise:
        return List<Map<String, String>>.from(_exerciseHistory);
      case PreviousInputs.newSession:
        return const <Map<String, String>>[];
    }
  }

  /// For debugging/inspection.
  List<Map<String, String>> get allHistory => List.unmodifiable(_allHistory);
  List<Map<String, String>> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
  List<Map<String, String>> get exerciseHistory =>
      List.unmodifiable(_exerciseHistory);
}

/// The transport of one call, reading the `usage` block off the response on
/// its way to `dart_openai` (#183).
///
/// The package parses `usage` into models without `prompt_tokens_details`,
/// so the cached share of the input never reaches the connector through
/// them; the raw body does. The bytes pass through untouched, and the body
/// is read once it is complete — before the package's own parse returns, so
/// [callUsage] is known by the time the call is.
///
/// Wraps the connector's injected client when there is one (a test's
/// scripted socket), and otherwise a client of its own for this one call,
/// which [close] releases.
class _UsageTap extends http.BaseClient {
  _UsageTap(http.Client? client)
    : _inner = client ?? http.Client(),
      _ownsInner = client == null;

  final http.Client _inner;
  final bool _ownsInner;
  TokenUsage? _usage;

  /// What the call cost, once its response has been read to the end;
  /// `null` before that and for a response without a usage block.
  CallUsage? callUsage(String model) {
    final usage = _usage;
    return usage == null ? null : CallUsage(model: model, tokens: usage);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final body = BytesBuilder();
    final tapped = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          body.add(chunk);
          sink.add(chunk);
        },
        handleDone: (sink) {
          _usage = usageInResponseBody(
            utf8.decode(body.takeBytes(), allowMalformed: true),
          );
          sink.close();
        },
      ),
    );
    return http.StreamedResponse(
      tapped,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (_ownsInner) _inner.close();
  }
}

/// The `usage` block of a chat.completions response [body] (#183): the
/// top-level one of a completion, or — for a stream asked for it with
/// `stream_options.include_usage` — the one on the last `data:` chunk.
/// `null` when the body carries none: an error, a stream that did not ask,
/// a stream cut off before its last chunk.
@visibleForTesting
TokenUsage? usageInResponseBody(String body) {
  final trimmed = body.trimLeft();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map ? TokenUsage.fromOpenAi(decoded['usage']) : null;
    } on FormatException {
      return null;
    }
  }
  TokenUsage? last;
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith('data:')) continue;
    final data = line.substring('data:'.length).trim();
    // Every chunk of such a stream has a `usage` key, `null` but on the
    // last one; only that one has counts in it.
    if (!data.contains('prompt_tokens')) continue;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) continue;
      last = TokenUsage.fromOpenAi(decoded['usage']) ?? last;
    } on FormatException {
      continue;
    }
  }
  return last;
}
