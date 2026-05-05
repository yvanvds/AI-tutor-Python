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
    return CodeTheme(
      data: CodeThemeData(styles: tutorCodeTheme),
      child: CodeField(
        controller: ref.read(codeServiceProvider).controller,
        textStyle: AppMono.code(),
        background: AppColors.ink0,
        gutterStyle: GutterStyle(
          textStyle: AppMono.code(color: AppColors.fgFaint, size: 13),
          background: AppColors.ink0,
          width: 44,
        ),
        expands: true,
      ),
    );
  }
}
