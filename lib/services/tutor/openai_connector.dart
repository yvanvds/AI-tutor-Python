import 'package:ai_tutor_python/data/config/global_config_providers.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:dart_openai/src/core/models/responses/responses.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OpenaiConnector {
  final Ref ref;
  OpenaiConnector({required this.ref});

  final String _apiKey = Env.apiKey;
  String? _previousResponseId;

  // in case request failed, we can resend it
  String? _previousPreviousResponseId;
  String? _previousInstuctions;
  String? _previousInput;

  Future<dynamic> sendRequest({
    required String instructions,
    required String input,
    bool newSession = false,
  }) async {
    //print("Starting OpenAI session with input: $input");
    _previousPreviousResponseId = _previousResponseId;
    _previousInput = input;
    _previousInstuctions = instructions;

    OpenAI.apiKey = _apiKey;

    // Await the config once here
    final cfg = await ref.read(globalConfigFutureProvider.future);
    final model = (cfg?.model.isNotEmpty ?? false) ? cfg!.model : 'gpt-4o';

    try {
      final response = await OpenAI.instance.responses.create(
        input: input,
        instructions: instructions,
        model: model,
        // if _previousResponseId is null, we start a new session anyway
        previousResponseId: newSession ? null : _previousResponseId,
      );
      _previousResponseId = response.id;
      //_printResponseRaw(response);
      return response.output;
    } catch (e) {
      return e;
    }
  }

  Future<dynamic> resendRequest() async {
    _previousResponseId = _previousPreviousResponseId;
    final result = await sendRequest(
      instructions: _previousInstuctions!,
      input: _previousInput!,
    );
    return result;
  }

  void _printResponseRaw(OpenAiResponse response) {
    print("Background: ${response.background}");
    print("conversation: ${response.conversation}");
    print("CreatedAt: ${response.createdAt}");
    print("error: ${response.error}");
    print("id: ${response.id}");
    print("incompleteDetails: ${response.incompleteDetails?.reason}");
    print("instructions: ${response.instructions}");
    print("maxOutputTokens: ${response.maxOutputTokens}");
    print("maxToolCalls: ${response.maxToolCalls}");
    print("metadata: ${response.metadata}");
    print("model: ${response.model}");
    print("output: ${response.output}");
    print("parallelToolCalls: ${response.parallelToolCalls}");
    print("previousResponseId: ${response.previousResponseId}");
    print("prompt: ${response.prompt}");
    print("promptCacheKey: ${response.promptCacheKey}");
    print("reasoning: ${response.reasoning}");
    print("safetyIdentifier: ${response.safetyIdentifier}");
    print("serviceTier: ${response.serviceTier}");
    print("status: ${response.status}");
    print("temperature: ${response.temperature}");
    print("text: ${response.text}");
    print("toolChoice: ${response.toolChoice}");
    print("tools: ${response.tools}");
    print("topLogprobs: ${response.topLogprobs}");
    print("topP: ${response.topP}");
    print("truncation: ${response.truncation}");
    print("store: ${response.store}");
    print("usage: ${response.usage}");
  }
}
