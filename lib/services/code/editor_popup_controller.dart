// The package does not export its popup controller; extending it is the
// fix for a bug inside it (#330), so it is imported from where it lives.
import 'package:flutter/animation.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/wip/autocomplete/popup_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// flutter_code_editor's dropdown controller, with a scroll controller its
/// popup actually attaches (#330).
///
/// The dropdown is at most 100 px tall, so a longer list scrolls. An arrow
/// key that selects a row out of view makes `scrollByArrow` scroll the list
/// through `itemScrollController.jumpTo`. But in flutter_code_editor 0.3.5
/// the popup hands that controller to its list only when it is already
/// attached, which it then never becomes: the jump ran into a null check
/// ("Null check operator used on a null value") and the app showed its
/// crash screen. Up from the first row wraps to the last, so it crashed
/// too.
///
/// Here the controller says it is attached, so the popup hands it to its
/// list and the list attaches it, and a jump is only made once it really
/// is. Each dropdown that opens anew gets a fresh controller: the package
/// draws each opening in a new overlay entry, and when one closes and the
/// next opens in the same frame, the old list detaches its controller only
/// after the new list has attached its own.
class EditorPopupController extends PopupController {
  EditorPopupController({required super.onCompletionSelected});

  _PopupScrollController _scroll = _PopupScrollController();

  @override
  ItemScrollController get itemScrollController => _scroll;

  @override
  void show(List<String> suggestions) {
    if (enabled && !shouldShow) _scroll = _PopupScrollController();
    super.show(suggestions);
  }
}

class _PopupScrollController extends ItemScrollController {
  /// Always "attached", so that the package's popup hands this controller
  /// to its list — see [EditorPopupController].
  @override
  bool get isAttached => true;

  @override
  void jumpTo({required int index, double alignment = 0}) {
    if (super.isAttached) super.jumpTo(index: index, alignment: alignment);
  }

  @override
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) async {
    if (!super.isAttached) return;
    return super.scrollTo(
      index: index,
      alignment: alignment,
      duration: duration,
      curve: curve,
      opacityAnimationWeights: opacityAnimationWeights,
    );
  }
}
