/// Locale-independent description of a system line the tutor flow wants to
/// show in chat (issue #23).
///
/// Services (`TutorService`, `Conductor`, `OpenaiConnector`, the response
/// parser) have no `BuildContext`, so they never produce user-facing text.
/// They emit a [ChatNotice]; `ChatService` stores it on the system message's
/// metadata and the chat widget resolves it against `AppLocalizations` at
/// render time — which also means a language switch re-renders the pills
/// already on screen.
enum ChatNoticeKind {
  /// "Something went wrong with the tutor: {cause}". [ChatNotice.cause]
  /// carries the underlying failure.
  tutorFailed,

  /// "The session could not start: {cause}".
  sessionStartFailed,

  /// Cosmos transient failure that outlived the client's retries.
  databaseUnavailable,

  /// OpenAI request timed out (connect or idle).
  tutorTimeout,

  /// Socket / HTTP failure reaching OpenAI.
  tutorUnreachable,

  /// Stream ended before the envelope closed.
  replyTruncated,

  /// Retry requested with nothing to retry.
  noPreviousRequest,

  /// Assistant returned no text at all.
  emptyResponse,

  /// Assistant text was neither an envelope nor legacy JSON. `args[0]` is
  /// the raw text.
  unparseableResponse,

  /// Envelope META carried a `type` no handler knows. `args[0]` is the type.
  unknownResponseType,

  /// A parsed response that no dispatch entry matched.
  unknownResponse,

  subgoalDeletedRedirect,
  subgoalSaturated,
  noGoalsLeft,
  emptyObjectives,
  preparingExercise,
  feedbackDegraded,

  /// `args[0]` is the goal title.
  newGoalSelected,

  /// `args[0]` / `args[1]` are `QuestionDifficulty` names (before / after).
  difficultyChanged,

  submitViaEditor,

  /// Verbatim text authored elsewhere (an LLM `error` reply, an unknown
  /// exception's `toString()`). `args[0]` is the text.
  raw,
}

class ChatNotice {
  const ChatNotice(this.kind, {this.args = const [], this.cause});

  /// Verbatim text that has no localized form.
  factory ChatNotice.raw(String text) =>
      ChatNotice(ChatNoticeKind.raw, args: [text]);

  final ChatNoticeKind kind;
  final List<String> args;
  final ChatNotice? cause;

  static const String metadataKey = 'notice';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (args.isNotEmpty) 'args': args,
    if (cause != null) 'cause': cause!.toJson(),
  };

  /// Inverse of [toJson]; `null` for anything that is not a notice map.
  static ChatNotice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kindName = raw['kind'];
    if (kindName is! String) return null;
    ChatNoticeKind? kind;
    for (final k in ChatNoticeKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    final rawArgs = raw['args'];
    final args = rawArgs is List
        ? rawArgs.map((a) => a.toString()).toList(growable: false)
        : const <String>[];
    return ChatNotice(kind, args: args, cause: fromJson(raw['cause']));
  }

  @override
  bool operator ==(Object other) =>
      other is ChatNotice &&
      other.kind == kind &&
      other.cause == cause &&
      _listEquals(other.args, args);

  @override
  int get hashCode => Object.hash(kind, cause, Object.hashAll(args));

  @override
  String toString() => 'ChatNotice(${toJson()})';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
