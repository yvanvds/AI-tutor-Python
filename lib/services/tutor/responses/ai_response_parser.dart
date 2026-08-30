import 'dart:convert';

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/envelope_assembler.dart';
import 'package:ai_tutor_python/services/tutor/responses/error_summary.dart';

class AIResponseParser {
  /// Parse a complete assistant message into a typed [ChatResponse].
  ///
  /// Tries the `<TEXT>...</TEXT><META>{...}</META>` envelope first (the
  /// streaming contract), then falls back to legacy JSON-only output for
  /// older instructions or non-compliant responses.
  static ChatResponse parse(String raw) {
    if (raw.trim().isEmpty) {
      return ErrorResponse(
        type: 'error',
        message: 'Empty response from the tutor.',
        notice: const ChatNotice(ChatNoticeKind.emptyResponse),
      );
    }

    final assembler = EnvelopeAssembler()
      ..add(raw)
      ..close();

    if (assembler.sawOpenTag) {
      return _fromEnvelope(assembler.text, assembler.metaRaw, raw);
    }
    return _fromLegacyJson(raw);
  }

  /// Build a [ChatResponse] from envelope pieces. Injects [text] under the
  /// `prompt` key (and `message` for error type) so the existing per-type
  /// `fromMap` factories keep working unchanged.
  static ChatResponse fromEnvelopePieces(String text, String metaRaw) =>
      _fromEnvelope(text, metaRaw, '$text<META>$metaRaw</META>');

  static ChatResponse _fromEnvelope(String text, String metaRaw, String raw) {
    final cleanedMeta = _stripCodeFences(metaRaw).trim();
    Map<String, dynamic>? metaMap;
    if (cleanedMeta.isNotEmpty) {
      try {
        final decoded = json.decode(cleanedMeta);
        if (decoded is Map<String, dynamic>) {
          metaMap = decoded;
        }
      } catch (_) {
        // fall through
      }
    }

    if (metaMap == null) {
      // META missing or malformed. If we at least have streamed text, try
      // legacy JSON parsing of that text (it may be raw JSON sent inside
      // <TEXT> by a confused model). Otherwise surface the raw text.
      final fromText = _tryLegacyJson(text);
      if (fromText != null) return fromText;
      if (text.isNotEmpty) {
        return ErrorResponse(type: 'error', message: text);
      }
      return _unparseable(raw);
    }

    final type = (metaMap['type'] as String?)?.toLowerCase() ?? '';
    final merged = <String, dynamic>{...metaMap};
    if (type == 'error') {
      merged['message'] = text;
    } else {
      merged['prompt'] = text;
    }
    try {
      return ChatResponseFactory.fromMap(merged);
    } catch (e) {
      return ErrorResponse(type: 'error', message: e.toString());
    }
  }

  static ChatResponse _fromLegacyJson(String raw) {
    final parsed = _tryLegacyJson(raw);
    if (parsed != null) return parsed;
    return _unparseable(raw);
  }

  static ErrorResponse _unparseable(String raw) => ErrorResponse(
        type: 'error',
        message: 'Could not process the response: $raw',
        notice: ChatNotice(ChatNoticeKind.unparseableResponse, args: [raw]),
      );

  static ChatResponse? _tryLegacyJson(String raw) {
    final cleaned = _stripCodeFences(raw).trim();
    if (!(cleaned.startsWith('{') || cleaned.startsWith('['))) return null;
    try {
      final decoded = json.decode(cleaned);
      Map<String, dynamic>? map;
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        map = (decoded.first as Map).cast<String, dynamic>();
      }
      if (map == null) return null;
      return ChatResponseFactory.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  static String _stripCodeFences(String s) {
    final fence = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      multiLine: false,
    );
    final match = fence.firstMatch(s.trim());
    return (match != null) ? match.group(1)! : s;
  }
}
