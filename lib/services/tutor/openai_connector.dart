import 'dart:convert';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/material.dart';

enum PreviousInputs { includeAll, includeSession, newSession }

class OpenaiConnector {
  final String _apiKey = Env.apiKey;

  // for resend
  String? _previousInstuctions;
  String? _previousInput;

  // Full history (spans sessions) and current-session history.
  // Each entry is a Responses API content item: {"role": "...", "content": "..."}.
  final List<Map<String, dynamic>> _allHistory = [];
  final List<Map<String, dynamic>> _sessionHistory = [];

  Future<dynamic> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    // store previous request info for possible resend
    _previousInput = input;
    _previousInstuctions = instructions;

    OpenAI.apiKey = _apiKey;

    final cfg = await DataService.globalConfig.getConfig();
    final model = (cfg?.model.isNotEmpty ?? false) ? cfg!.model : 'gpt-4o';

    if (inputs == PreviousInputs.newSession) {
      // clear session history for this one-off fresh session
      _sessionHistory.clear();
    }
    // Build a working copy of history and append THIS user turn
    final workingHistory = _historyFor(inputs)
      ..add({"role": "user", "content": input});

    assert(() {
      debugPrint(const JsonEncoder.withIndent('  ').convert(workingHistory));
      return true;
    }());

    OpenAI.requestsTimeOut = Duration(seconds: 60);

    try {
      final response = await OpenAI.instance.responses.create(
        // IMPORTANT: pass message objects, not plain strings
        input: workingHistory,
        instructions: instructions, // must be resent each call
        model: model,
        store: false, // you're managing state client-side
      );

      // Only if the request succeeded, permanently record this user turn
      // into the chosen scopes.
      if (inputs != PreviousInputs.newSession) {
        _sessionHistory.add({"role": "user", "content": input});
      }
      _allHistory.add({"role": "user", "content": input});

      // Return the model output as-is for your caller;
      // you’ll call addResponse(...) once you wrap it as ChatResponse.
      return response.output;
    } catch (e) {
      return e;
    }
  }

  Future<dynamic> resendRequest() async {
    return sendRequest(
      instructions: _previousInstuctions!,
      input: _previousInput!,
    );
  }

  /// Record the assistant turn into history (skip errors).
  /// This matches your request: user -> sendRequest(), agent -> addResponse().
  void addResponse(ChatResponse response) {
    if (response is! ErrorResponse) {
      final jsonString = jsonEncode(response.toJson());
      _allHistory.add({"role": "assistant", "content": jsonString});
      _sessionHistory.add({"role": "assistant", "content": jsonString});
    }
  }

  /// Optional helpers if you ever want to add raw assistant text
  /// (e.g., for debugging before you map to ChatResponse).
  void addAssistantRaw(String text) {
    _allHistory.add({"role": "assistant", "content": text});
    _sessionHistory.add({"role": "assistant", "content": text});
  }

  /// If you need to manually start a fresh session boundary.
  void startNewSession() {
    _sessionHistory.clear();
  }

  /// Build a working copy of the history based on the requested scope.
  List<Map<String, dynamic>> _historyFor(PreviousInputs scope) {
    return List<Map<String, dynamic>>.from(
      scope == PreviousInputs.includeAll
          ? _allHistory
          : scope == PreviousInputs.includeSession
          ? _sessionHistory
          : <Map<String, dynamic>>[],
    );
  }

  /// For debugging/inspection
  List<Map<String, dynamic>> get allHistory => List.unmodifiable(_allHistory);
  List<Map<String, dynamic>> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
}
