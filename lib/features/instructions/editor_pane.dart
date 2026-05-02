import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

class EditorPane extends StatelessWidget {
  const EditorPane({super.key, required this.controller});
  final CodeController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF23241F),
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        expands: true,
        maxLines: null,
        minLines: null,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 16,
          color: Color(0xFFF8F8F2),
        ),
        cursorColor: const Color(0xFFF8F8F2),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }
}
