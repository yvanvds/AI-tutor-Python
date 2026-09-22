import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

/// Bottom-anchored shell shared by every composer state. Reports its measured
/// height to [ComposerHeightNotifier] so the message list pads itself.
///
/// `flutter_chat_ui` draws the composer *over* the list (a `Positioned` in a
/// `Stack`) and pads the list by whatever the notifier last reported, so a
/// height that goes stale hides the bottom of the newest message behind the
/// composer. `initState` / `didUpdateWidget` alone are not enough (#146): the
/// idle composer's `TextField` has `maxLines: null`, so wrapping onto another
/// row is a *relayout of the child*, not a new `ComposerChrome` widget, and
/// neither hook fires. A [SizeChangedLayoutNotifier] catches that case — and
/// every other composer state's growth — by watching the rendered size.
class ComposerChrome extends StatefulWidget {
  const ComposerChrome({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.s,
      AppSpacing.lg,
      AppSpacing.s,
    ),
    this.background,
    this.topBorder,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults resolve at build time rather than in the parameter list: the
  /// palette they come from is swappable (#32), so a default baked into the
  /// constructor would freeze one theme's colours.
  final Color? background;
  final Color? topBorder;

  @override
  State<ComposerChrome> createState() => _ComposerChromeState();
}

class _ComposerChromeState extends State<ComposerChrome> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant ComposerChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // The notification is dispatched from `performLayout`, so the re-measure
      // waits for the end of the frame: `setHeight` notifies listeners, and
      // rebuilding the list's padding mid-layout is not allowed.
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
          return true;
        },
        child: SizeChangedLayoutNotifier(
          child: Container(
            key: _key,
            decoration: BoxDecoration(
              color: widget.background ?? AppColors.ink1,
              border: Border(
                top: BorderSide(
                  color: widget.topBorder ?? AppColors.ink2,
                  width: 1,
                ),
              ),
            ),
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  void _measure() {
    if (!mounted) return;
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    context.read<ComposerHeightNotifier>().setHeight(renderBox.size.height);
  }
}
