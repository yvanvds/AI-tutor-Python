import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

class EditorPane extends StatelessWidget {
  const EditorPane({required this.controller});
  final CodeController controller;

  @override
  Widget build(BuildContext context) {
    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: CodeField(
        controller: controller,
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        expands: true,
        padding: const EdgeInsets.all(16),
        wrap: true,
      ),
    );
  }
}
