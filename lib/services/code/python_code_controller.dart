import 'dart:async';

import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:ai_tutor_python/services/code/editor_popup_controller.dart';
import 'package:ai_tutor_python/services/code/python_completion.dart';
import 'package:ai_tutor_python/services/code/python_reference.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';

/// The controller of the Python editor in Practice and Playground:
/// flutter_code_editor's own, with a dropdown after a dot that lists what
/// the value or module before it offers (#322).
///
/// The package suggests Python's keywords and the words already in the
/// buffer, and knows nothing of what stands before a dot: after `t.f` it
/// offered `for`, `float`, `False`, whatever `t` was. After a dot in code
/// the suggestions now come from [memberSuggestions] — the receiver's
/// members from [PythonReference], each shown with its parameters — and
/// there are none when the receiver's type is unknown. Without a dot the
/// package's suggestions stay as they were.
///
/// A copy or a cut out of the editor is remembered as a copy made in the
/// app (#334), so it pastes back where a paste from outside does not.
class PythonCodeController extends CodeController {
  /// [reference] stands in for the bundled one (tests); without it the
  /// bundled reference is read at the first dot.
  PythonCodeController({super.text, PythonReference? reference})
    : super(language: python) {
    _reference = reference;
    // The package's own one crashes on an arrow key that scrolls the
    // dropdown (#330). Set here, before any field listens to it.
    popupController = EditorPopupController(
      onCompletionSelected: insertSelectedWord,
    );
  }

  PythonReference? _reference;

  /// The package's own actions, with its copy — Ctrl+C, Ctrl+Insert, Ctrl+X,
  /// Shift+Delete and the editor's menu — remembering what it copies (#334).
  @override
  Map<Type, Action<Intent>> get actions => _actions ??= {
    ...super.actions,
    CopySelectionTextIntent: _RememberingCopyAction(
      this,
      super.actions[CopySelectionTextIntent]!
          as Action<CopySelectionTextIntent>,
    ),
  };
  Map<Type, Action<Intent>>? _actions;

  /// The members the open dropdown lists, in its order; null while it lists
  /// the package's own words, or nothing.
  List<ReferenceItem>? _members;

  /// Bumped by every suggestion request: a request still waiting for the
  /// reference to load must not open a dropdown over a newer keystroke.
  int _request = 0;

  @override
  Future<void> generateSuggestions() async {
    final request = ++_request;
    final cursor = _fullCursor();
    if (cursor == null || memberAccessAt(fullText, cursor) == null) {
      _members = null;
      return super.generateSuggestions();
    }
    final reference = _reference ??= await PythonReference.load();
    if (request != _request) return;
    // Read the caret again: it may have moved while the reference loaded.
    final now = _fullCursor();
    final members = now == null
        ? null
        : memberSuggestions(reference, fullText, now);
    if (members == null || members.isEmpty) {
      _members = null;
      popupController.hide();
      return;
    }
    _members = members;
    popupController.show([for (final m in members) m.signature]);
  }

  /// Puts the chosen member's name after the dot, in place of what was typed
  /// of it, with the caret right after the name — no space, no brackets: the
  /// editor closes a `(` the student types itself.
  @override
  void insertSelectedWord() {
    final members = _members;
    if (members == null) return super.insertSelectedWord();
    final index = popupController.selectedIndex;
    final access = selection.isCollapsed
        ? memberAccessAt(text, selection.baseOffset)
        : null;
    if (access == null || index < 0 || index >= members.length) {
      popupController.hide();
      return;
    }
    final name = members[index].name;
    value = TextEditingValue(
      text: text.replaceRange(access.nameStart, access.wordEnd, name),
      selection: TextSelection.collapsed(
        offset: access.nameStart + name.length,
      ),
    );
    // The edit above asked for suggestions again; the choice is made.
    _members = null;
    popupController.hide();
  }

  /// The caret's offset in [fullText] (folded blocks included), or null
  /// without a single caret.
  int? _fullCursor() {
    final s = selection;
    if (!s.isValid || !s.isCollapsed) return null;
    return code.hiddenRanges.recoverSelection(s).baseOffset;
  }
}

/// The package's copy, after noting what it puts on the clipboard: the
/// selection with the folded lines in it, as the package copies it.
class _RememberingCopyAction extends Action<CopySelectionTextIntent> {
  _RememberingCopyAction(this._controller, this._copy);

  final PythonCodeController _controller;
  final Action<CopySelectionTextIntent> _copy;

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    final selection = _controller.code.hiddenRanges.recoverSelection(
      _controller.value.selection,
    );
    if (selection.isValid && !selection.isCollapsed) {
      InAppClipboard.instance.remember(
        selection.textInside(_controller.code.text),
      );
    }
    return _copy.invoke(intent);
  }
}
