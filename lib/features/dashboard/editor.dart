import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/features/dashboard/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

class Editor extends ConsumerStatefulWidget {
  const Editor({super.key, required this.controller});
  final EditorController controller;

  @override
  ConsumerState<Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<Editor> {
  late CodeController _controller;

  // Prevent feedback loop when we programmatically set the text
  bool _settingFromProvider = false;

  @override
  void initState() {
    super.initState();

    final initial = ref.read(codeProvider);
    _controller = CodeController(text: initial, language: python);

    // Keep the EditorController in sync
    widget.controller.bind(getValue: () => _controller.fullText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(codeProvider);
    _controller.text = code;

    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: CodeField(
        controller: _controller,
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 20),
        expands: true,
      ),
    );
  }
}
