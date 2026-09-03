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
  ScriptedLlm(Iterable<String> replies) : _replies = [...replies];

  final List<String> _replies;

  /// Requests the app opened, and how many of those were retries of a reply
  /// the app refused to use.
  int sends = 0;
  int resends = 0;

  /// The user-turn payload of every non-streaming request, in order — a
  /// flow asserts on what the app *told* the model (#99: the grade
  /// justification prompt carries the computed number as a fixed fact).
  final List<String> sentInputs = <String>[];

  /// What is left unplayed — a flow asserts this is empty when it expected
  /// every scripted reply to be consumed.
  int get remaining => _replies.length;

  String? _take() => _replies.isEmpty ? null : _replies.removeAt(0);

  Stream<StreamChunk> _play(String input) {
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
    return assembleStream(
      Stream.value(reply),
      input: input,
      inputs: PreviousInputs.includeSession,
    );
  }

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    sends++;
    return _play(input);
  }

  @override
  Stream<StreamChunk> resendRequestStream() {
    resends++;
    return _play('');
  }

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    sends++;
    sentInputs.add(input);
    return _reply();
  }

  @override
  Future<ConnectorResult> resendRequest() async {
    resends++;
    return _reply();
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
