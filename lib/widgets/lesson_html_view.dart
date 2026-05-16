import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_all/webview_all.dart';

import '../theme/tokens.dart';

/// Renders an authored lesson HTML body fragment inside a WebView.
///
/// The fragment is wrapped at render time in a minimal HTML document with
/// the shared `assets/lesson/lesson.css` stylesheet inlined as a `<style>`
/// block. CSS is read once and cached for the process lifetime.
///
/// The WebView only consumes [fragment]; layout chrome (headers, buttons,
/// counters) stays in surrounding Flutter widgets. JS in the fragment runs
/// inside the WebView sandbox — there is no Flutter↔JS bridge.
class LessonHtmlView extends StatefulWidget {
  const LessonHtmlView({super.key, required this.fragment});

  /// Body inner HTML — what goes inside `<body class="lesson">`. Not a full
  /// document; do not include `<html>` / `<head>` / `<body>` tags.
  final String fragment;

  @override
  State<LessonHtmlView> createState() => _LessonHtmlViewState();
}

class _LessonHtmlViewState extends State<LessonHtmlView> {
  static String? _cachedCss;
  static const _cssAssetKey = 'assets/lesson/lesson.css';

  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.ink0);
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fragment != widget.fragment) {
      _load();
    }
  }

  Future<void> _load() async {
    final css = await _loadCss();
    final doc = _wrapDocument(widget.fragment, css);
    await _controller.loadHtmlString(doc);
    if (mounted) setState(() => _ready = true);
  }

  static Future<String> _loadCss() async {
    final cached = _cachedCss;
    if (cached != null) return cached;
    final loaded = await rootBundle.loadString(_cssAssetKey);
    _cachedCss = loaded;
    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink0,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_ready)
            const Positioned.fill(
              child: ColoredBox(color: AppColors.ink0),
            ),
        ],
      ),
    );
  }
}

String _wrapDocument(String fragment, String css) {
  return '<!doctype html>'
      '<html><head>'
      '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>$css</style>'
      '</head>'
      '<body class="lesson">$fragment</body>'
      '</html>';
}
