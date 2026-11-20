import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/python_code_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CodeService {
  /// Placeholder a fresh editor buffer starts with.
  static const String starterText = '# Start coding here';

  late PythonCodeController controller;
  CodeService() {
    controller = PythonCodeController(text: starterText);
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

/// Per-mode editor buffer. Practice and Playground keep independent
/// `CodeController`s so switching mode preserves what the student was
/// typing in each. Explain mode has no editor but is included so call
/// sites can pass the current `modeProvider` value without special-casing.
final codeServiceProvider = Provider.family<CodeService, SessionMode>((
  ref,
  mode,
) {
  final s = CodeService();
  ref.onDispose(s.dispose);
  return s;
});
