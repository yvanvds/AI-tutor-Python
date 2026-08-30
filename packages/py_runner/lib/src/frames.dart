import 'dart:convert';

import 'package:meta/meta.dart';

/// Wire-protocol v1 frames. See `PYTHON_IMPLEMENTATION.md` §2.2.
///
/// Frames are one-line JSON objects exchanged between Flutter and the host
/// `python.exe` over stdin/stdout. Each frame carries a `type` field; unknown
/// fields are preserved by the codec but ignored by handlers.
///
/// Two directions:
///   * [HostInboundFrame]  — Flutter → host (`exec`, `cancel`, `input_response`)
///   * [HostOutboundFrame] — host → Flutter (`ready`, `stdout`, `stderr`,
///     `input_request`, `exception`, `done`, `host_log`)

@immutable
sealed class Frame {
  const Frame();

  String get type;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());
}

@immutable
sealed class HostInboundFrame extends Frame {
  const HostInboundFrame();

  static HostInboundFrame decode(String line) {
    final decoded = _decodeObject(line);
    final type = decoded['type'];
    return switch (type) {
      'exec' => ExecFrame._fromJson(decoded),
      'cancel' => CancelFrame._fromJson(decoded),
      'input_response' => InputResponseFrame._fromJson(decoded),
      _ => throw FrameDecodeException('unknown inbound frame type: $type'),
    };
  }
}

@immutable
sealed class HostOutboundFrame extends Frame {
  const HostOutboundFrame();

  static HostOutboundFrame decode(String line) {
    final decoded = _decodeObject(line);
    final type = decoded['type'];
    return switch (type) {
      'ready' => ReadyFrame._fromJson(decoded),
      'stdout' => StdoutFrame._fromJson(decoded),
      'stderr' => StderrFrame._fromJson(decoded),
      'input_request' => InputRequestFrame._fromJson(decoded),
      'exception' => ExceptionFrame._fromJson(decoded),
      'done' => DoneFrame._fromJson(decoded),
      'host_log' => HostLogFrame._fromJson(decoded),
      _ => throw FrameDecodeException('unknown outbound frame type: $type'),
    };
  }
}

/// Thrown when a line cannot be parsed as a frame. Callers (the line pump in
/// step 4) decide whether to drop the line, log it, or shut the host down.
class FrameDecodeException implements Exception {
  FrameDecodeException(this.message);

  final String message;

  @override
  String toString() => 'FrameDecodeException: $message';
}

// ---------------------------------------------------------------------------
// Flutter -> host
// ---------------------------------------------------------------------------

@immutable
final class ExecFrame extends HostInboundFrame {
  const ExecFrame({
    required this.id,
    required this.code,
    this.cwd,
    this.timeoutMs,
  });

  factory ExecFrame._fromJson(Map<String, Object?> json) => ExecFrame(
    id: _requireString(json, 'id'),
    code: _requireString(json, 'code'),
    cwd: _optionalString(json, 'cwd'),
    timeoutMs: _optionalInt(json, 'timeout_ms'),
  );

  final String id;
  final String code;
  final String? cwd;

  /// Optional run timeout in milliseconds. Null means no timeout.
  final int? timeoutMs;

  @override
  String get type => 'exec';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'code': code,
    if (cwd != null) 'cwd': cwd,
    if (timeoutMs != null) 'timeout_ms': timeoutMs,
  };
}

@immutable
final class CancelFrame extends HostInboundFrame {
  const CancelFrame({required this.id});

  factory CancelFrame._fromJson(Map<String, Object?> json) =>
      CancelFrame(id: _requireString(json, 'id'));

  final String id;

  @override
  String get type => 'cancel';

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id};
}

@immutable
final class InputResponseFrame extends HostInboundFrame {
  const InputResponseFrame({
    required this.id,
    required this.requestId,
    required this.value,
  });

  factory InputResponseFrame._fromJson(Map<String, Object?> json) =>
      InputResponseFrame(
        id: _requireString(json, 'id'),
        requestId: _requireInt(json, 'request_id'),
        value: _requireString(json, 'value'),
      );

  final String id;
  final int requestId;
  final String value;

  @override
  String get type => 'input_response';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'request_id': requestId,
    'value': value,
  };
}

// ---------------------------------------------------------------------------
// host -> Flutter
// ---------------------------------------------------------------------------

@immutable
final class ReadyFrame extends HostOutboundFrame {
  const ReadyFrame({
    required this.pythonVersion,
    required this.platform,
    required this.capabilities,
    this.protocolVersion,
  });

  factory ReadyFrame._fromJson(Map<String, Object?> json) => ReadyFrame(
    pythonVersion: _requireString(json, 'python_version'),
    platform: _requireString(json, 'platform'),
    capabilities: _requireStringList(json, 'capabilities'),
    protocolVersion: _optionalInt(json, 'protocol_version'),
  );

  final String pythonVersion;
  final String platform;
  final List<String> capabilities;

  /// host.py emits a `protocol_version` integer alongside the spec fields.
  /// The spec table in §2.2 doesn't list it, so it stays optional — unknown
  /// fields are ignored on both sides per the forward-compat rule.
  final int? protocolVersion;

  @override
  String get type => 'ready';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'python_version': pythonVersion,
    'platform': platform,
    'capabilities': List<String>.unmodifiable(capabilities),
    if (protocolVersion != null) 'protocol_version': protocolVersion,
  };
}

@immutable
final class StdoutFrame extends HostOutboundFrame {
  const StdoutFrame({required this.id, required this.text});

  factory StdoutFrame._fromJson(Map<String, Object?> json) => StdoutFrame(
    id: _requireString(json, 'id'),
    text: _requireString(json, 'text'),
  );

  final String id;
  final String text;

  @override
  String get type => 'stdout';

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id, 'text': text};
}

@immutable
final class StderrFrame extends HostOutboundFrame {
  const StderrFrame({required this.id, required this.text});

  factory StderrFrame._fromJson(Map<String, Object?> json) => StderrFrame(
    id: _requireString(json, 'id'),
    text: _requireString(json, 'text'),
  );

  final String id;
  final String text;

  @override
  String get type => 'stderr';

  @override
  Map<String, Object?> toJson() => {'type': type, 'id': id, 'text': text};
}

@immutable
final class InputRequestFrame extends HostOutboundFrame {
  const InputRequestFrame({
    required this.id,
    required this.requestId,
    required this.prompt,
  });

  factory InputRequestFrame._fromJson(Map<String, Object?> json) =>
      InputRequestFrame(
        id: _requireString(json, 'id'),
        requestId: _requireInt(json, 'request_id'),
        prompt: _requireString(json, 'prompt'),
      );

  final String id;
  final int requestId;
  final String prompt;

  @override
  String get type => 'input_request';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'request_id': requestId,
    'prompt': prompt,
  };
}

@immutable
final class ExceptionFrame extends HostOutboundFrame {
  const ExceptionFrame({
    required this.id,
    required this.excType,
    required this.message,
    required this.traceback,
  });

  factory ExceptionFrame._fromJson(Map<String, Object?> json) => ExceptionFrame(
    id: _requireString(json, 'id'),
    excType: _requireString(json, 'exc_type'),
    message: _requireString(json, 'message'),
    traceback: _requireString(json, 'traceback'),
  );

  final String id;
  final String excType;
  final String message;
  final String traceback;

  @override
  String get type => 'exception';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'exc_type': excType,
    'message': message,
    'traceback': traceback,
  };
}

enum DoneStatus {
  ok('ok'),
  error('error'),
  cancelled('cancelled');

  const DoneStatus(this.wire);

  final String wire;

  static DoneStatus fromWire(String value) {
    for (final status in DoneStatus.values) {
      if (status.wire == value) return status;
    }
    throw FrameDecodeException('unknown done status: $value');
  }
}

@immutable
final class DoneFrame extends HostOutboundFrame {
  const DoneFrame({
    required this.id,
    required this.status,
    required this.durationMs,
  });

  factory DoneFrame._fromJson(Map<String, Object?> json) => DoneFrame(
    id: _requireString(json, 'id'),
    status: DoneStatus.fromWire(_requireString(json, 'status')),
    durationMs: _requireInt(json, 'duration_ms'),
  );

  final String id;
  final DoneStatus status;
  final int durationMs;

  @override
  String get type => 'done';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'status': status.wire,
    'duration_ms': durationMs,
  };
}

enum HostLogLevel {
  info('info'),
  warn('warn'),
  error('error');

  const HostLogLevel(this.wire);

  final String wire;

  static HostLogLevel fromWire(String value) {
    for (final level in HostLogLevel.values) {
      if (level.wire == value) return level;
    }
    throw FrameDecodeException('unknown host_log level: $value');
  }
}

@immutable
final class HostLogFrame extends HostOutboundFrame {
  const HostLogFrame({required this.level, required this.message});

  factory HostLogFrame._fromJson(Map<String, Object?> json) => HostLogFrame(
    level: HostLogLevel.fromWire(_requireString(json, 'level')),
    message: _requireString(json, 'message'),
  );

  final HostLogLevel level;
  final String message;

  @override
  String get type => 'host_log';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'level': level.wire,
    'message': message,
  };
}

// ---------------------------------------------------------------------------
// shared decode helpers
// ---------------------------------------------------------------------------

Map<String, Object?> _decodeObject(String line) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException catch (e) {
    throw FrameDecodeException('invalid JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw FrameDecodeException('frame is not a JSON object');
  }
  return decoded;
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FrameDecodeException(
    'field "$key" must be a string (got ${value.runtimeType})',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  // Lenient: a wrong-typed optional field is treated as absent. Same
  // forward-compat spirit as the unknown-fields rule in §2.2.
  return value is String ? value : null;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FrameDecodeException(
    'field "$key" must be an int (got ${value.runtimeType})',
  );
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is int ? value : null;
}

List<String> _requireStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FrameDecodeException(
      'field "$key" must be a list (got ${value.runtimeType})',
    );
  }
  final result = <String>[];
  for (var i = 0; i < value.length; i++) {
    final item = value[i];
    if (item is! String) {
      throw FrameDecodeException(
        'field "$key"[$i] must be a string (got ${item.runtimeType})',
      );
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}
