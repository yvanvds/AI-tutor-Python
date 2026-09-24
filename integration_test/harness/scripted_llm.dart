// A stand-in for OpenAI that replays canned assistant *text* (#78).
//
// Deliberately not a mock of the parsed response: each script entry is the
// raw `<TEXT>…</TEXT><META>{…}</META>` string a model would emit, and it goes
// through the connector's real `assembleStream` — envelope assembly, response
// parsing, validation — so a flow exercises the production path from the wire
// down. Retries pull the next entry, which is how a flow scripts "the model
// got it wrong, then got it right".

import 'dart:convert';

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';

class ScriptedLlm extends OpenaiConnector {
  ScriptedLlm(Iterable<String> replies, {this.probeResults = const {}})
    : _replies = [...replies];

  final List<String> _replies;

  /// What the Test button in Options gets back, per model id (#125). An id
  /// not listed fails the way an unknown id fails at OpenAI, so a flow that
  /// forgot to script a probe sees the failure on screen rather than a
  /// passing test it never asked for.
  final Map<String, ModelProbe> probeResults;

  /// Every model id the Test button asked about, in order (#125).
  final List<String> probed = <String>[];

  /// Requests the app opened, and how many of those were retries of a reply
  /// the app refused to use.
  int sends = 0;
  int resends = 0;

  /// The user-turn payload of every request, streaming or not, in order — a
  /// flow asserts on what the app *told* the model (#99: the grade
  /// justification prompt carries the computed number as a fixed fact;
  /// #132: a question typed on a theory page carries the page).
  final List<String> sentInputs = <String>[];

  /// The system prompt of every request, streaming or not, in order — a flow
  /// asserts on the contract the app put in front of the model (#117: the
  /// output-language directive follows the language picked in Options).
  final List<String> sentInstructions = <String>[];

  /// The history scope of every request, streaming or not, in order (#184).
  final List<PreviousInputs> sentScopes = <PreviousInputs>[];

  /// The conversation history every request carried in front of its input,
  /// in order (#184) — what the model would have read before it. Kept by
  /// the connector's own bookkeeping, so a flow sees the real scope.
  final List<List<Map<String, String>>> sentHistories =
      <List<Map<String, String>>>[];

  String _lastInput = '';
  PreviousInputs _lastScope = PreviousInputs.includeSession;

  /// What is left unplayed — a flow asserts this is empty when it expected
  /// every scripted reply to be consumed.
  int get remaining => _replies.length;

  String? _take() => _replies.isEmpty ? null : _replies.removeAt(0);

  void _open(String input, PreviousInputs inputs) {
    sends++;
    sentInputs.add(input);
    sentScopes.add(inputs);
    sentHistories.add(historyForCall(inputs));
    _lastInput = input;
    _lastScope = inputs;
  }

  Stream<StreamChunk> _play(String input, PreviousInputs inputs) {
    final reply = _take();
    if (reply == null) {
      return Stream.value(
        StreamFailed(
          StateError('ScriptedLlm: script exhausted'),
          StackTrace.current,
          ChatNotice.raw('script exhausted'),
        ),
      );
    }
    return assembleStream(Stream.value(reply), input: input, inputs: inputs);
  }

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    _open(input, inputs);
    sentInstructions.add(instructions);
    return _play(input, inputs);
  }

  @override
  Stream<StreamChunk> resendRequestStream() {
    resends++;
    return _play(_lastInput, _lastScope);
  }

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    _open(input, inputs);
    sentInstructions.add(instructions);
    return _reply();
  }

  @override
  Future<ConnectorResult> resendRequest() async {
    resends++;
    return _reply();
  }

  @override
  Future<ModelProbe> probe(String model) async {
    probed.add(model);
    return probeResults[model] ??
        ModelProbeFailed(
          StateError('ScriptedLlm: no probe scripted for $model'),
          StackTrace.current,
          ChatNotice.raw(
            'The model `$model` does not exist or you do not have access '
            'to it.',
          ),
        );
  }

  ConnectorResult _reply() {
    final reply = _take();
    if (reply == null) {
      final e = StateError('ScriptedLlm: script exhausted');
      return ConnectorFailure(
        e,
        StackTrace.current,
        ChatNotice.raw('script exhausted'),
      );
    }
    return ConnectorOk(reply);
  }
}

/// One assistant turn in the envelope the app's instructions demand.
String llmEnvelope({required String text, required String meta}) =>
    '<TEXT>$text</TEXT><META>$meta</META>';

/// A `complete_code` exercise turn. [code] is embedded verbatim, so a flow
/// can script one with a blank and one without.
String completeCodeReply({
  required String text,
  required String code,
}) => llmEnvelope(
  text: text,
  meta:
      '{"type":"complete_code","code":"'
      '${code.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}'
      '"}',
);

/// A `code_feedback` grading turn (LLM_CONTRACT "What the grader returns").
/// Each entry of [loSignals] is one `{subgoalId, loId, signal, strength}`
/// map, exactly as the grader emits it; each entry of [transferLOs] (#101)
/// is one `{subgoalId, loId}` map naming a previously mastered LO the code
/// correctly used. The field is omitted when the list is empty, as a grader
/// with nothing to nominate would.
String codeFeedbackReply({
  required String text,
  required String quality,
  List<Map<String, String>> loSignals = const [],
  List<Map<String, String>> transferLOs = const [],
}) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'code_feedback',
    'suggestion': '',
    'overallQuality': quality,
    'loSignals': loSignals,
    if (transferLOs.isNotEmpty) 'transferLOs': transferLOs,
  }),
);
