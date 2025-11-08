import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';

class CodeService {
  late CodeController controller;
  CodeService() {
    controller = CodeController(text: "# Start coding here", language: python);
  }

  void setText(String code) {
    controller.fullText = code;
    controller.selection = TextSelection.collapsed(offset: code.length);
    controller.clearComposing();
  }

  String getText() {
    return controller.fullText;
  }

  void dispose() {
    controller.dispose();
  }
}
