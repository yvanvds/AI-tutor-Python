import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Editor extends ConsumerWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    return CodeTheme(
      data: CodeThemeData(styles: tutorCodeTheme),
      child: CodeField(
        controller: ref.read(codeServiceProvider(mode)).controller,
        textStyle: AppMono.code(),
        background: AppColors.ink0,
        gutterStyle: GutterStyle(
          textStyle: AppMono.code(color: AppColors.fgFaint, size: 13),
          background: AppColors.ink0,
          // `width` is the WHOLE gutter, and flutter_code_editor 0.3.5 spends
          // 42 px of it before the numbers: a fixed 16 px issue column, a
          // fixed 16 px folding column and the 10 px `margin` (#145). At 44
          // the number column was 2 px, so `10` wrapped onto two rows (`1` /
          // `0`) and every row below it slid out of line with its code line.
          // Hiding a column does not help — the package subtracts the same
          // 16 px from `width`, so the numbers always get `width - 42`.
          // 72 leaves 30 px, and the package renders the numbers at the code
          // text size (14, the `size: 13` above only carries the colour),
          // where three digits measure ~26 px.
          width: 72,
        ),
        expands: true,
      ),
    );
  }
}
