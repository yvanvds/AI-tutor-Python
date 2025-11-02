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
  late final ProviderSubscription<String> _codeSub;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: ref.read(codeProvider), // seed once
      language: python, // your syntax
    );

    // Keep the EditorController in sync
    widget.controller.bind(getValue: () => _controller.fullText);

    // Provider → Controller (when codeProvider changes elsewhere)
    _codeSub = ref.listenManual<String>(codeProvider, (prev, next) {
      if (_controller.text != next) {
        _controller.value = TextEditingValue(text: next);
      }
    }, fireImmediately: false);

    // Controller → Provider (user types)
    // _controller.addListener(() {
    //   final current = ref.read(codeProvider);
    //   final text = _controller.text;
    //   if (current != text) {
    //     ref.read(codeProvider.notifier).state = text; // or .set(text)
    //   }
    // });
  }

  @override
  void dispose() {
    _codeSub.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(codeProvider);

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
