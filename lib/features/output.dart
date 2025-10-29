import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:ai_tutor_python/features/output_controller.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:py_engine_desktop/py_engine_desktop.dart';

class Output extends StatefulWidget {
  const Output({super.key, required this.controller});

  final OutputController controller;

  @override
  State<Output> createState() => _OutputState();
}

class _OutputState extends State<Output> {
  bool _initialized = false;
  bool _running = false;
  final _scrollCtrl = ScrollController();

  StreamSubscription<String>? stdout;
  StreamSubscription<String>? stderr;

  // Live output
  final List<_Line> _lines = [];

  // Current process + subscriptions
  PythonScript?
  _pythonScript; // type from py_engine_desktop (e.g. PythonScript)

  @override
  void initState() {
    super.initState();
    _initializePython();

    // Register runner callback
    widget.controller.bind(run: _runCode, stop: () => _forceStop());
  }

  Future<void> _initializePython() async {
    try {
      await PyEngineDesktop.init();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _lines
          ..clear()
          ..add(_Line('[Engine init failed] $e', isError: true));
      });
    }
  }

  Future<void> _runCode(String code) async {
    // If already running, cancel
    await _forceStop();

    setState(() {
      _running = true;
      _lines
        ..clear()
        ..add(_Line('▶ Running script...', isMeta: true));
    });

    try {
      // Write to a temp file
      final tempDir = await getTemporaryDirectory();
      final scriptFile = File(path.join(tempDir.path, 'student_script.py'));
      await scriptFile.writeAsString(code);

      // Start script
      _pythonScript = await PyEngineDesktop.startScript(scriptFile.path);

      if (_pythonScript == null) {
        throw StateError('Failed to start Python script');
      }

      stdout = _pythonScript!.stdout.listen((line) {
        if (_lines.length > 10000) {
          // close the stream
          _pythonScript!.stop();
          return;
        }
        setState(() => _lines.add(_Line(line)));
        _autoScrollToBottom();
      });

      stderr = _pythonScript!.stderr.listen((line) {
        if (_lines.length > 1000) {
          _pythonScript!.stop();
          return;
        }
        setState(() => _lines.add(_Line(line, isError: true)));
        _autoScrollToBottom();
      });

      // Wait for completion
      final exit = await _pythonScript?.exitCode;

      setState(() {
        _running = false;
        _lines.add(_Line('■ Exit code: $exit', isMeta: true));
        _autoScrollToBottom();
      });
    } catch (e) {
      setState(() {
        _running = false;
        _lines.add(_Line('[Runtime error] $e', isError: true));
        _autoScrollToBottom();
      });
    } finally {
      _pythonScript = null;
      _running = false;

      setState(() {});
    }
  }

  void _autoScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _forceStop() async {
    if (_pythonScript != null) {
      await PyEngineDesktop.stopScript(_pythonScript!);
    }
  }

  @override
  void dispose() {
    _forceStop();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                _running ? 'Running…' : 'Output',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              if (_running)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _scrollCtrl,
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: _lines.length,
                itemBuilder: (context, i) {
                  final line = _lines[i];
                  final color = line.isMeta
                      ? Theme.of(context).hintColor
                      : line.isError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).textTheme.bodyMedium?.color;
                  return SelectableText(
                    line.text,
                    style: TextStyle(fontFamily: 'monospace', color: color),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line {
  final String text;
  final bool isError;
  final bool isMeta;
  _Line(this.text, {this.isError = false, this.isMeta = false});
}
