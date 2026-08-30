import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

/// Bottom-anchored shell shared by every composer state. Reports its measured
/// height to [ComposerHeightNotifier] so the message list pads itself.
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
    );
  }

  void _measure() {
    if (!mounted) return;
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    context.read<ComposerHeightNotifier>().setHeight(renderBox.size.height);
  }
}
