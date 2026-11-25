import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/code_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/paste_guard.dart';
import 'package:ai_tutor_python/widgets/submit_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ctrl+Y redoes, as it does in every Windows program (#339). Neither
/// Flutter nor flutter_code_editor 0.3.5 binds it — both know only
/// Ctrl+Shift+Z (Cmd+Shift+Z on a Mac), which keeps working. The intent is
/// the one the package's Ctrl+Shift+Z sends, so the same redo of the
/// package's own history handles it: the field's [EditableText] hands
/// [RedoTextIntent] on to the controller's actions.
const Map<ShortcutActivator, Intent> _redoShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoTextIntent(
    SelectionChangedCause.keyboard,
  ),
};

/// The code editor of Practice and Playground. Ctrl+Enter (Cmd+Enter on a
/// Mac) runs the code, as the Run button above it does (#300). The
/// package's own Enter binding matches a plain Enter only, so the two do not
/// meet; the chat composer has its own focus and keeps Ctrl+Enter for send.
/// Ctrl+Y redoes ([_redoShortcuts]); the composer leaves it alone.
///
/// A paste from outside the app does not reach the editor (#334): Ctrl+V,
/// Shift+Insert and the right-click menu meet a [PasteGuard], which shows
/// the editor's menu itself — the package's field takes no menu of the
/// app's. What the student copied in the app pastes as before.
///
/// Each editor stays on the buffer of the mode whose page it is on (#322).
/// The session view fades the old mode's page out while the new one fades
/// in, so for a moment both editors are mounted; one that followed
/// `modeProvider` would switch to the new mode's buffer in that moment, and
/// two fields would share one buffer and its dropdown.
class Editor extends ConsumerStatefulWidget {
  const Editor({super.key});

  @override
  ConsumerState<Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<Editor> {
  /// The mode of the page this editor is on: the current one when the page
  /// mounts, which it does because the mode switched to it.
  late final SessionMode _mode = ref.read(modeProvider);

  late final CodeController _controller = ref
      .read(codeServiceProvider(_mode))
      .controller;

  /// The dropdown after a dot (#322) keeps its open state on the controller,
  /// which outlives this editor: left open, it would still take Enter, Tab
  /// and the arrow keys when the page comes back, with nothing on screen.
  /// So it closes when the editor goes — a mode switch, or a multiple-choice
  /// question taking the editor's place.
  void _closeDropdown() => _controller.popupController.hide();

  @override
  void dispose() {
    // The field has already taken the dropdown off the screen; only the
    // open state is left. Not through `hide()`: its notification would
    // rebuild the dropdown's widget while the tree is being torn down.
    _controller.popupController.shouldShow = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // At the switch itself, not when the fade ends: the dropdown is drawn in
    // the app's overlay and would not fade with the page.
    ref.listen<SessionMode>(modeProvider, (_, next) {
      if (next != _mode) _closeDropdown();
    });
    return CallbackShortcuts(
      bindings: submitShortcutBindings(() => runEditorCode(ref, _mode)),
      child: Shortcuts(
        shortcuts: _redoShortcuts,
        child: PasteGuard(takesOverContextMenu: true, child: _codeField()),
      ),
    );
  }

  Widget _codeField() {
    return CodeTheme(
      data: CodeThemeData(styles: tutorCodeTheme),
      child: CodeField(
        controller: _controller,
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
