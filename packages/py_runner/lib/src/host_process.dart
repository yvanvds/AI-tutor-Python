import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'frames.dart';

/// Owns one `python.exe` subprocess running `host.py`. Decodes the host's
/// stdout into [HostOutboundFrame]s and lets callers send [HostInboundFrame]s
/// on stdin.
///
/// Higher-level orchestration (run lifecycle, cancellation, status, frame
/// dispatch by id) lives in `PyRunner`; this class is a dumb pipe.
class HostProcess {
  HostProcess._({
    required Process process,
    required Stream<HostOutboundFrame> frames,
    required Stream<String> stderrLines,
    required Stream<FrameDecodeException> decodeErrors,
  })  : _process = process,
        _frames = frames,
        _stderrLines = stderrLines,
        _decodeErrors = decodeErrors;

  final Process _process;
  final Stream<HostOutboundFrame> _frames;
  final Stream<String> _stderrLines;
  final Stream<FrameDecodeException> _decodeErrors;

  /// Single-subscription stream of decoded outbound frames. Closes when the
  /// host process exits.
  Stream<HostOutboundFrame> get frames => _frames;

  /// Broadcast stream of host-internal stderr lines (host.py's own diagnostics
  /// — never student program output, which is wrapped into [StderrFrame] on
  /// stdout). Stderr is drained eagerly so the OS pipe buffer can't fill up.
  Stream<String> get stderrLines => _stderrLines;

  /// Broadcast stream of malformed lines that failed to decode.
  Stream<FrameDecodeException> get decodeErrors => _decodeErrors;

  int get pid => _process.pid;

  /// Spawns `python.exe -s -X utf8 -u <hostScript>` with the env vars host.py
  /// expects. The `-s` + `PYTHONNOUSERSITE=1` pair keeps the interpreter
  /// hermetic against any user-site `%APPDATA%\Roaming\Python\…` shadow that a
  /// co-installed system Python would otherwise contribute (see
  /// PYTHON_IMPLEMENTATION.md §6 risks).
  static Future<HostProcess> spawn({
    required String pythonExecutable,
    required String hostScript,
    String? workingDirectory,
    Map<String, String> extraEnvironment = const <String, String>{},
  }) async {
    final env = <String, String>{
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUNBUFFERED': '1',
      'PYTHONNOUSERSITE': '1',
      ...extraEnvironment,
    };

    final process = await Process.start(
      pythonExecutable,
      <String>['-s', '-X', 'utf8', '-u', hostScript],
      environment: env,
      workingDirectory: workingDirectory,
      includeParentEnvironment: true,
      runInShell: false,
    );

    process.stdin.encoding = utf8;

    final frameController = StreamController<HostOutboundFrame>();
    final decodeErrorController =
        StreamController<FrameDecodeException>.broadcast();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.isEmpty) return;
        try {
          frameController.add(HostOutboundFrame.decode(line));
        } on FrameDecodeException catch (e) {
          if (!decodeErrorController.isClosed) {
            decodeErrorController.add(e);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!frameController.isClosed) {
          frameController.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!frameController.isClosed) frameController.close();
        if (!decodeErrorController.isClosed) decodeErrorController.close();
      },
    );

    final stderrController = StreamController<String>.broadcast();
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (!stderrController.isClosed) stderrController.add(line);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!stderrController.isClosed) {
          stderrController.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!stderrController.isClosed) stderrController.close();
      },
    );

    return HostProcess._(
      process: process,
      frames: frameController.stream,
      stderrLines: stderrController.stream,
      decodeErrors: decodeErrorController.stream,
    );
  }

  /// Encodes [frame] as one UTF-8 JSON line and writes it on stdin.
  ///
  /// Bytes are written directly via [IOSink.add] so neither the system locale
  /// nor [IOSink.encoding] can corrupt non-ASCII characters in student code or
  /// in `input_response` payloads.
  void send(HostInboundFrame frame) {
    _process.stdin.add(utf8.encode('${frame.encode()}\n'));
  }

  /// Closes stdin (signals graceful shutdown) and awaits process exit.
  /// Hard-kills if the process doesn't exit within [grace].
  Future<int> shutdown({
    Duration grace = const Duration(seconds: 2),
  }) async {
    try {
      await _process.stdin.close();
    } catch (_) {
      // stdin may already be closed if the process died first.
    }
    try {
      return await _process.exitCode.timeout(grace);
    } on TimeoutException {
      _process.kill();
      return _process.exitCode;
    }
  }

  /// Best-effort terminate. Use [shutdown] for graceful exit.
  void kill() {
    _process.kill();
  }
}
