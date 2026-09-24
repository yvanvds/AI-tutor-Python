// What the tutor's LLM calls cost, in tokens (#183).
//
// Every chat.completions response carries a `usage` block. The connector
// reads it off each call ([CallUsage]), the tutor adds the calls up until a
// graded turn is written ([UsageLedger]), and the turn record keeps the sum
// with a split per kind of call ([TurnUsage]). The teacher's Students page
// adds the records up per class. Tokens, not money: the price per token is
// OpenAI's and changes; it does not belong in the app.

import 'package:ai_tutor_python/core/chat_request_type.dart';

/// Token counts of one or more chat.completions calls, as OpenAI reports
/// them.
class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.cachedTokens = 0,
    this.completionTokens = 0,
  });

  /// Input tokens, the cached ones included: OpenAI's `prompt_tokens`.
  final int promptTokens;

  /// The part of [promptTokens] served from OpenAI's prompt cache:
  /// `prompt_tokens_details.cached_tokens`, 0 when the response has none.
  final int cachedTokens;

  /// Output tokens, reasoning included: `completion_tokens`.
  final int completionTokens;

  static const TokenUsage zero = TokenUsage();

  /// Input tokens that did not come from the cache. With [cachedTokens]
  /// and [completionTokens] it splits the call three ways without
  /// overlap: what is billed at the full input rate, at the cached rate
  /// and at the output rate.
  int get uncachedPromptTokens =>
      promptTokens > cachedTokens ? promptTokens - cachedTokens : 0;

  bool get isZero =>
      promptTokens == 0 && cachedTokens == 0 && completionTokens == 0;

  TokenUsage operator +(TokenUsage other) => TokenUsage(
    promptTokens: promptTokens + other.promptTokens,
    cachedTokens: cachedTokens + other.cachedTokens,
    completionTokens: completionTokens + other.completionTokens,
  );

  /// Reads OpenAI's `usage` object, from a completion or from the last
  /// chunk of a stream that asked for it (`stream_options.include_usage`).
  /// `null` when [raw] is not one: a missing block, `"usage": null` on the
  /// other chunks of a stream, or counts that are not numbers.
  static TokenUsage? fromOpenAi(Object? raw) {
    if (raw is! Map) return null;
    final prompt = raw['prompt_tokens'];
    final completion = raw['completion_tokens'];
    if (prompt is! num || completion is! num) return null;
    final details = raw['prompt_tokens_details'];
    final cached = details is Map ? details['cached_tokens'] : null;
    return TokenUsage(
      promptTokens: prompt.toInt(),
      cachedTokens: cached is num ? cached.toInt() : 0,
      completionTokens: completion.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'cachedTokens': cachedTokens,
    'completionTokens': completionTokens,
  };

  /// Reads what [toJson] wrote. A missing or malformed count is 0, so a
  /// partial doc adds nothing rather than failing a whole sum.
  static TokenUsage fromJson(Object? raw) {
    if (raw is! Map) return zero;
    int count(Object? v) => v is num ? v.toInt() : 0;
    return TokenUsage(
      promptTokens: count(raw['promptTokens']),
      cachedTokens: count(raw['cachedTokens']),
      completionTokens: count(raw['completionTokens']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TokenUsage &&
      other.promptTokens == promptTokens &&
      other.cachedTokens == cachedTokens &&
      other.completionTokens == completionTokens;

  @override
  int get hashCode => Object.hash(promptTokens, cachedTokens, completionTokens);

  @override
  String toString() =>
      'TokenUsage(prompt: $promptTokens, cached: $cachedTokens, '
      'completion: $completionTokens)';
}

/// What one call cost, and the model it went to.
class CallUsage {
  const CallUsage({required this.model, required this.tokens});

  /// The model the request named.
  final String model;
  final TokenUsage tokens;

  @override
  bool operator ==(Object other) =>
      other is CallUsage && other.model == model && other.tokens == tokens;

  @override
  int get hashCode => Object.hash(model, tokens);

  @override
  String toString() => 'CallUsage($model, $tokens)';
}

/// The kinds of call a turn record splits its usage into.
enum UsageCallKind {
  /// Generating the exercise's question.
  question,

  /// Grading the student's answer to it.
  grading,

  /// Grading the answer to a follow-up question.
  followUp,

  /// A hint.
  hint,

  /// A question the student typed, about the exercise or about the page
  /// on screen.
  dialogue,

  /// The status report the conductor asks for after a subgoal.
  status;

  static UsageCallKind of(ChatRequestType type) => switch (type) {
    ChatRequestType.socraticQuestion ||
    ChatRequestType.mcQuestion ||
    ChatRequestType.explainCodeQuestion ||
    ChatRequestType.completeCodeQuestion ||
    ChatRequestType.writeCodeQuestion => question,
    ChatRequestType.submitCode ||
    ChatRequestType.mcqAnswer ||
    ChatRequestType.explainAnswer ||
    ChatRequestType.socraticFeedback => grading,
    ChatRequestType.followUpAnswer => followUp,
    ChatRequestType.requestHint => hint,
    ChatRequestType.studentQuestion ||
    ChatRequestType.contentQuestion => dialogue,
    ChatRequestType.status || ChatRequestType.noResult => status,
  };

  static UsageCallKind? parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// What the calls behind one turn record cost together (#183): the sum,
/// the split per kind of call, and the model.
class TurnUsage {
  const TurnUsage({required this.byCall, this.model});

  /// Tokens per kind of call. Kinds that made no call are absent.
  final Map<UsageCallKind, TokenUsage> byCall;

  /// The model of the last call. The calls of one record normally all go
  /// to the same one; a model switched mid-exercise shows as the new one.
  final String? model;

  TokenUsage get total =>
      byCall.values.fold(TokenUsage.zero, (sum, u) => sum + u);

  /// The sum sits at the top of the block, so a query or a dump can add
  /// records up without walking the split.
  Map<String, dynamic> toJson() => {
    if (model != null) 'model': model,
    ...total.toJson(),
    'byCall': {for (final e in byCall.entries) e.key.name: e.value.toJson()},
  };

  /// Reads what [toJson] wrote; `null` for a doc without the block —
  /// every record written before #183. Unknown call kinds are dropped.
  static TurnUsage? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final byCall = <UsageCallKind, TokenUsage>{};
    final split = raw['byCall'];
    if (split is Map) {
      for (final e in split.entries) {
        final kind = UsageCallKind.parse(e.key);
        if (kind != null) byCall[kind] = TokenUsage.fromJson(e.value);
      }
    }
    final model = raw['model'];
    return TurnUsage(byCall: byCall, model: model is String ? model : null);
  }

  @override
  bool operator ==(Object other) {
    if (other is! TurnUsage || other.model != model) return false;
    if (other.byCall.length != byCall.length) return false;
    for (final e in byCall.entries) {
      if (other.byCall[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    model,
    Object.hashAllUnordered(
      byCall.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'TurnUsage($model, $byCall)';
}

/// Adds up the calls made since the last graded turn was written.
///
/// Normally that is one exercise: its question, the grading, a hint, a
/// follow-up. What happened in between without a record of its own rides
/// along with the next one — a status report, a question the student left
/// ungraded — so the records together account for every call that came
/// back with a usage block.
class UsageLedger {
  final Map<UsageCallKind, TokenUsage> _byCall = {};
  String? _model;

  bool get isEmpty => _byCall.isEmpty;

  void add(UsageCallKind kind, CallUsage usage) {
    _byCall[kind] = (_byCall[kind] ?? TokenUsage.zero) + usage.tokens;
    _model = usage.model;
  }

  /// What was added since the last take, and a fresh start. `null` when no
  /// call reported anything.
  TurnUsage? take() {
    if (_byCall.isEmpty) return null;
    final out = TurnUsage(byCall: Map.of(_byCall), model: _model);
    clear();
    return out;
  }

  void clear() {
    _byCall.clear();
    _model = null;
  }
}
