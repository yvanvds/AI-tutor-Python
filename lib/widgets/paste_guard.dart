import 'dart:async';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:ai_tutor_python/services/clipboard/paste_policy.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a student writes an answer, a chat message or Playground code
/// (#334): a paste from outside the app does not reach the text field below.
///
/// Every paste route meets it. Ctrl+V and Shift+Insert — and Windows'
/// clipboard history (Win+V), which pastes with Ctrl+V — send the field's
/// [PasteTextIntent], which this overrides. "Paste" in the context menu does
/// too: [inAppContextMenu] sends it as the keyboard does. A field takes that
/// menu as its `contextMenuBuilder`; a field that takes none (the code
/// editor's) gets it from here, with [takesOverContextMenu].
///
/// At a paste the clipboard is read. Text the student copied in the app
/// ([InAppClipboard]) is pasted as before; anything else is not: a short
/// neutral notice says so ([showPasteBlockedNotice]), and the attempt and
/// its length are noted for the oefening ([blockedPasteLedgerProvider]).
/// Typing works as before. With `BlockExternalPaste: false` in the school's
/// `config/global` every paste goes through.
///
/// A copy or a cut out of the field — keyboard or menu — is remembered, so
/// it can be pasted again.
class PasteGuard extends ConsumerStatefulWidget {
  const PasteGuard({
    super.key,
    required this.child,
    this.takesOverContextMenu = false,
  });

  final Widget child;

  /// Whether a right-click in [child] opens [inAppContextMenu] from here
  /// instead of the field's own menu, whose "Paste" would not ask: for a
  /// field that takes no `contextMenuBuilder` (flutter_code_editor's
  /// `CodeField`). The right-click acts as one in a text field on Windows:
  /// in a field without focus it puts the caret where it was made, in the
  /// focused field it keeps the selection.
  final bool takesOverContextMenu;

  @override
  ConsumerState<PasteGuard> createState() => _PasteGuardState();
}

class _PasteGuardState extends ConsumerState<PasteGuard> {
  final ContextMenuController _menu = ContextMenuController();

  late final Map<Type, Action<Intent>> _actions = {
    PasteTextIntent: _GuardedPasteAction(this),
    CopySelectionTextIntent: RememberCopyAction(),
  };

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  /// Whether what is on the clipboard may be pasted: always with the block
  /// switched off, else when it is empty or a copy made in the app. A paste
  /// that may not is noted and told.
  Future<bool> _mayPaste() async {
    final config = ref.exists(globalConfigServiceProvider)
        ? ref.read(globalConfigServiceProvider)
        : null;
    if (!externalPasteBlocked(config)) return true;
    final ledger = ref.read(blockedPasteLedgerProvider);
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    // Nothing to paste: the field's own paste does nothing either.
    if (text == null || text.isEmpty) return true;
    if (InAppClipboard.instance.holds(text)) return true;
    // Its characters as the student would have seen them; the text itself
    // is not kept.
    ledger.note(text.replaceAll('\r\n', '\n').runes.length);
    if (mounted) showPasteBlockedNotice(context);
    return false;
  }

  void _openMenu(Offset position) {
    final field = _fieldBelow();
    if (field == null) return;
    _closeMenu();
    final render = field.renderEditable;
    render.handleSecondaryTapDown(TapDownDetails(globalPosition: position));
    if (!field.widget.focusNode.hasFocus) {
      render.selectPosition(cause: SelectionChangedCause.tap);
      field.requestKeyboard();
    }
    // Paste is offered once the clipboard is known to hold text, as in the
    // field's own menu.
    field.clipboardStatus.update();
    _menu.show(
      context: context,
      contextMenuBuilder: (menuContext) => TextFieldTapRegion(
        // Part of the field for its focus, but its own region to close on a
        // click anywhere else.
        child: TapRegion(
          onTapOutside: (_) => _closeMenu(),
          child: ListenableBuilder(
            listenable: field.clipboardStatus,
            builder: (menuContext, _) => inAppContextMenu(
              menuContext,
              field,
              close: _closeMenu,
              anchor: position,
            ),
          ),
        ),
      ),
    );
    HardwareKeyboard.instance.addHandler(_closeOnKey);
  }

  bool _closeOnKey(KeyEvent event) {
    if (event is KeyDownEvent) _closeMenu();
    return false;
  }

  void _closeMenu() {
    HardwareKeyboard.instance.removeHandler(_closeOnKey);
    _menu.remove();
  }

  /// The text field in [PasteGuard.child].
  EditableTextState? _fieldBelow() {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final guarded = Actions(actions: _actions, child: widget.child);
    if (!widget.takesOverContextMenu) return guarded;
    return RawGestureDetector(
      gestures: {
        _RightClickRecognizer:
            GestureRecognizerFactoryWithHandlers<_RightClickRecognizer>(
              () => _RightClickRecognizer(debugOwner: this),
              (recognizer) => recognizer.onRightClick = _openMenu,
            ),
      },
      child: guarded,
    );
  }
}

/// The field's own paste, after [_PasteGuardState._mayPaste] says it may.
class _GuardedPasteAction extends ContextAction<PasteTextIntent> {
  _GuardedPasteAction(this._guard);

  final _PasteGuardState _guard;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    // The field's own paste, bound to the field: known only while this call
    // runs.
    unawaited(_paste(callingAction, intent, context));
    return null;
  }

  Future<void> _paste(
    Action<PasteTextIntent>? paste,
    PasteTextIntent intent,
    BuildContext? context,
  ) async {
    if (!await _guard._mayPaste() || paste == null) return;
    // The field may have gone while the clipboard was read.
    if (context?.mounted == false) return;
    paste.invoke(intent);
  }
}

/// Remembers what a copy or a cut out of a text field puts on the clipboard
/// (#334), then lets the field copy as it would. Above a field, it takes the
/// field's [CopySelectionTextIntent]: Ctrl+C, Ctrl+Insert, Ctrl+X,
/// Shift+Delete and the menu of [inAppContextMenu].
class RememberCopyAction extends ContextAction<CopySelectionTextIntent> {
  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final copy = callingAction;
    final field = context?.findAncestorStateOfType<EditableTextState>();
    if (field != null) {
      final value = field.textEditingValue;
      final selection = value.selection;
      // What the field's copy puts on the clipboard; a cut in a field that
      // cannot be edited puts nothing there.
      final copies =
          selection.isValid &&
          !selection.isCollapsed &&
          !field.widget.obscureText &&
          !(intent.collapseSelection && field.widget.readOnly);
      if (copies) {
        InAppClipboard.instance.remember(selection.textInside(value.text));
      }
    }
    if (copy is ContextAction<CopySelectionTextIntent>) {
      return copy.invoke(intent, context);
    }
    return copy?.invoke(intent);
  }
}

/// [child] — a field that can be copied from, such as a [SelectableText] —
/// with its copies remembered as copies made in the app (#334). Give the
/// field [inAppContextMenu] too, for a copy from its menu.
class RememberCopies extends StatelessWidget {
  const RememberCopies({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      CopySelectionTextIntent: RememberCopyAction(),
    },
    child: child,
  );
}

/// A [SelectionArea] whose copies — Ctrl+C, Ctrl+Insert, Copy in its menu —
/// are remembered as copies made in the app (#334): the tutor's messages and
/// feedback, a quiz question.
class InAppSelectionArea extends StatefulWidget {
  const InAppSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<InAppSelectionArea> createState() => _InAppSelectionAreaState();
}

class _InAppSelectionAreaState extends State<InAppSelectionArea> {
  /// What is selected now: what a copy puts on the clipboard.
  String? _selected;

  late final Map<Type, Action<Intent>> _actions = {
    CopySelectionTextIntent: _RememberSelectionCopy(this),
  };

  void _remember() {
    final selected = _selected;
    if (selected != null) InAppClipboard.instance.remember(selected);
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: _actions,
    child: SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText,
      contextMenuBuilder: (context, region) =>
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: region.contextMenuAnchors,
            buttonItems: [
              for (final item in region.contextMenuButtonItems)
                if (item.type == ContextMenuButtonType.copy)
                  item.copyWith(
                    onPressed: () {
                      _remember();
                      item.onPressed?.call();
                    },
                  )
                else
                  item,
            ],
          ),
      child: widget.child,
    ),
  );
}

/// The selection area's own copy, after noting what it copies.
class _RememberSelectionCopy extends ContextAction<CopySelectionTextIntent> {
  _RememberSelectionCopy(this._area);

  final _InAppSelectionAreaState _area;

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final copy = callingAction;
    _area._remember();
    if (copy is ContextAction<CopySelectionTextIntent>) {
      return copy.invoke(intent, context);
    }
    return copy?.invoke(intent);
  }
}

/// The context menu of a text field (#334): its own items, with Cut, Copy
/// and Paste sent to the field as the keyboard sends them. So a paste from
/// the menu meets a [PasteGuard] above the field as Ctrl+V does, and a copy
/// meets [RememberCopyAction] — or the code editor's own copy — as Ctrl+C
/// does. [close] takes the menu away before an item acts; by default the
/// field's own toolbar is hidden. [anchor] places the menu; by default it
/// is where the field puts its own.
///
/// Fits a field's `contextMenuBuilder` as it is.
Widget inAppContextMenu(
  BuildContext context,
  EditableTextState field, {
  VoidCallback? close,
  Offset? anchor,
}) {
  void closeMenu() => close != null ? close() : field.hideToolbar();

  void send(Intent intent) {
    closeMenu();
    final target = field.widget.focusNode.context;
    if (target != null) Actions.maybeInvoke(target, intent);
  }

  final items = [
    for (final item in field.contextMenuButtonItems)
      switch (item.type) {
        ContextMenuButtonType.cut => item.copyWith(
          onPressed: () => send(
            const CopySelectionTextIntent.cut(SelectionChangedCause.toolbar),
          ),
        ),
        ContextMenuButtonType.copy => item.copyWith(
          onPressed: () => send(CopySelectionTextIntent.copy),
        ),
        ContextMenuButtonType.paste => item.copyWith(
          onPressed: () =>
              send(const PasteTextIntent(SelectionChangedCause.toolbar)),
        ),
        _ => item.copyWith(
          onPressed: () {
            closeMenu();
            item.onPressed?.call();
          },
        ),
      },
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchor == null
        ? field.contextMenuAnchors
        : TextSelectionToolbarAnchors(primaryAnchor: anchor),
    buttonItems: items,
  );
}

/// The notice under the app when a paste was blocked (#334): short and
/// neutral, so it does not read as an error of the app. It says nothing of
/// why, and nothing of what does work.
void showPasteBlockedNotice(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: pasteBlockedNoticeKey,
        content: Text(AppLocalizations.of(context).pasteGuard_blockedNotice),
      ),
    );
}

/// The key of the notice of [showPasteBlockedNotice].
const Key pasteBlockedNoticeKey = Key('paste-blocked-notice');

/// Claims a right-click in the field before the field does — at the press,
/// which the field's own recognizer, waiting for the release, then loses —
/// and reports where it was released.
class _RightClickRecognizer extends OneSequenceGestureRecognizer {
  _RightClickRecognizer({super.debugOwner})
    : super(allowedButtonsFilter: _rightButton);

  static bool _rightButton(int buttons) => buttons == kSecondaryButton;

  ValueChanged<Offset>? onRightClick;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent) {
      onRightClick?.call(event.position);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'right click';
}
