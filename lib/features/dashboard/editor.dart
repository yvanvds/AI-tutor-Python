import 'package:ai_tutor_python/features/dashboard/editor_controller.dart';
import 'package:flutter/material.dart';
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
  CodeController _controller = CodeController(
    text: '# Write your Python code here\n',
    language: python,
  );

  @override
  void initState() {
    super.initState();
    _initializeMonaco();

    widget.controller.bind(getValue: () => _controller.fullText);
  }

  Future<void> _initializeMonaco() async {
    _controller = CodeController(
      text: '# Write your Python code here\n',
      language: python,
    );

    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // /// Expose a method to get the current code
  // Future<String?> getCode() async {
  //   if (_controller == null) return null;
  //   final content = await _controller!.getValue();
  //   return content;
  // }

  @override
  Widget build(BuildContext context) {
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
