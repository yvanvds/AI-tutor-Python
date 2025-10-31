import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:dart_openai/src/core/models/responses/responses.dart';

class OpenaiConnector {
  final String _apiKey = Env.apiKey;
  String? _previousResponseId;

  Future<dynamic> sendRequest({
    required String instructions,
    required String input,
    bool newSession = false,
  }) async {
    print("Starting OpenAI session with input: $input");
    OpenAI.apiKey = _apiKey;
    final response = await OpenAI.instance.responses.create(
      input: input,
      instructions: instructions,
      model: "gpt-5-mini-2025-08-07",
      // if _previousResponseId is null, we start a new session anyway
      previousResponseId: newSession ? null : _previousResponseId,
    );
    _previousResponseId = response.id;
    printResponseRaw(response);
    return response.output;
  }

  void printResponseRaw(OpenAiResponse response) {
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
