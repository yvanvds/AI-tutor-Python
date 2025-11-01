import 'dart:convert';

import 'package:ai_tutor_python/core/chat_response_type.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';
import 'package:ai_tutor_python/services/tutor/responses/exercise.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/status_summary.dart';

class AIResponseParser {
  /// Parse a single AI response payload and return the typed model instance.
  /// Accepts either a decoded structure (List/Map) or a JSON string.
  static Object parse(dynamic jsonInput) {
    final textMap = extractFirstJsonMap(jsonInput);
    if (textMap != null) {
      final ChatResponseType t = _stringToType(
        textMap['type']?.toString() ?? '',
      );

      switch (t) {
        case ChatResponseType.exercise:
          return Exercise.fromMap(textMap);
        case ChatResponseType.answer:
          return Answer.fromMap(textMap);
        case ChatResponseType.hint:
          return Hint.fromMap(textMap);
        case ChatResponseType.codeFeedback:
          return CodeFeedback.fromMap(textMap);
        case ChatResponseType.mcqFeedback:
          return McqFeedback.fromMap(textMap);
        case ChatResponseType.explainFeedback:
          return ExplainFeedback.fromMap(textMap);
        case ChatResponseType.socraticFeedback:
          return SocraticFeedback.fromMap(textMap);
        case ChatResponseType.statusSummary:
          return StatusSummary.fromMap(textMap);
        case ChatResponseType.error:
          return ErrorResponse.fromMap(textMap);
      }
    } else {
      final raw = extractFirstTextString(jsonInput);
      if (raw == null) {
        return "No connection. I'll try again."; // truly missing content
      } else {
        return raw;
      }
    }
  }

  // ---------- helpers ----------

  static ChatResponseType _stringToType(String value) {
    switch (value) {
      case 'exercise':
        return ChatResponseType.exercise;
      case 'answer':
        return ChatResponseType.answer;
      case 'hint':
        return ChatResponseType.hint;
      case 'code_feedback':
        return ChatResponseType.codeFeedback;
      case 'mcq_feedback':
        return ChatResponseType.mcqFeedback;
      case 'explain_feedback':
        return ChatResponseType.explainFeedback;
      case 'socratic_feedback':
        return ChatResponseType.socraticFeedback;
      case 'status_summary':
        return ChatResponseType.statusSummary;
      case 'error':
        return ChatResponseType.error;
      default:
        throw FormatException('Unknown response type: $value');
    }
  }

  /// Get the FIRST text chunk as a raw String (most common case).
  static String? extractFirstTextString(dynamic jsonInput) {
    final all = extractAllTextStrings(jsonInput);
    return all.isEmpty ? null : all.first;
  }

  /// Get ALL text chunks as raw Strings.
  static List<String> extractAllTextStrings(dynamic jsonInput) {
    final dynamic data = (jsonInput is String)
        ? json.decode(jsonInput)
        : jsonInput;

    final List<dynamic> items = (data is List) ? data : [data];
    final List<String> results = [];

    for (final item in items) {
      if (item is! Map) continue;
      if (item['type'] == 'message' && item['content'] is List) {
        for (final contentItem in (item['content'] as List)) {
          if (contentItem is! Map) continue;
          if (contentItem['type'] == 'output_text') {
            final dynamic t = contentItem['text'];
            if (t is String) results.add(t);
            // If some providers return { text: { ... } } you can add:
            if (t is Map && t['value'] is String)
              results.add(t['value'] as String);
          }
        }
      }
    }
    return results;
  }

  /// Try to parse the FIRST text chunk as JSON Map.
  /// - Strips ```json fences
  /// - Accepts either object or array (returns first object if array)
  static Map<String, dynamic>? extractFirstJsonMap(dynamic jsonInput) {
    final text = extractFirstTextString(jsonInput);
    if (text == null) return null;

    final cleaned = _stripCodeFences(text).trim();

    // Quick guard: only try JSON if it looks like it.
    if (!(cleaned.startsWith('{') || cleaned.startsWith('['))) return null;

    try {
      final decoded = json.decode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return decoded.first as Map<String, dynamic>;
      }
    } catch (_) {
      // ignore parse errors; caller can fall back to raw text
    }
    return null;
  }

  static String _stripCodeFences(String s) {
    // Remove ```json ... ``` or ``` ... ```
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      multiLine: false,
    );
    final match = fence.firstMatch(s.trim());
    return (match != null) ? match.group(1)! : s;
  }
}
