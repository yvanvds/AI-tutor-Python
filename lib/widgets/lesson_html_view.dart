import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/widgets/lesson_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_all/webview_all.dart';

import '../theme/tokens.dart';

/// Renders an authored lesson HTML body fragment inside a WebView.
///
/// The fragment is wrapped at render time in a minimal HTML document with
/// the shared `assets/lesson/lesson.css` stylesheet inlined as a `<style>`
/// block. CSS is read once and cached for the process lifetime.
///
/// The WebView only consumes [fragment]; layout chrome (headers, buttons,
/// counters) stays in surrounding Flutter widgets.
///
/// Live previews (#13): every `<pre class="run">` block in the fragment
/// gets an output pane underneath. The page posts the block's code on the
/// [kLessonRunnerChannel] JavaScript channel, the host runs it through
/// [lessonCodeRunnerProvider] and pushes the result back into the page.
/// That is the only Flutter↔JS bridge; the authored HTML stays inert.
class LessonHtmlView extends ConsumerStatefulWidget {
  const LessonHtmlView({super.key, required this.fragment});

  /// Body inner HTML — what goes inside `<body class="lesson">`. Not a full
  /// document; do not include `<html>` / `<head>` / `<body>` tags.
  final String fragment;

  @override
  ConsumerState<LessonHtmlView> createState() => _LessonHtmlViewState();
}

class _LessonHtmlViewState extends ConsumerState<LessonHtmlView> {
  static String? _cachedCss;
  static const _cssAssetKey = 'assets/lesson/lesson.css';

  late final WebViewController _controller;
  late final Future<void> _channelReady;
  LessonRunnerLabels? _labels;
  bool _ready = false;

  /// Bumped on every load so a run that finishes after the page was
  /// replaced is dropped instead of delivered into the wrong document.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.ink0);
    // Registering the channel installs a document-created script, so it
    // has to land before the first `loadHtmlString`.
    _channelReady = _controller.addJavaScriptChannel(
      kLessonRunnerChannel,
      onMessageReceived: _onRunRequested,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = AppLocalizations.of(context);
    final labels = LessonRunnerLabels(
      output: l.lesson_run_output_label,
      run: l.lesson_run_button,
      running: l.lesson_run_running,
      unavailable: l.lesson_run_unavailable,
    );
    final previous = _labels;
    if (previous == null || !_sameLabels(previous, labels)) {
      _labels = labels;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant LessonHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fragment != widget.fragment) {
      _load();
    }
  }

  static bool _sameLabels(LessonRunnerLabels a, LessonRunnerLabels b) =>
      a.output == b.output &&
      a.run == b.run &&
      a.running == b.running &&
      a.unavailable == b.unavailable;

  Future<void> _load() async {
    final generation = ++_generation;
    final css = await _loadCss();
    await _channelReady;
    if (!mounted || generation != _generation) return;
    final doc = buildLessonDocument(
      fragment: widget.fragment,
      css: css,
      labels: _labels!,
    );
    await _controller.loadHtmlString(doc);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _onRunRequested(JavaScriptMessage message) async {
    final request = LessonRunRequest.tryParse(message.message);
    if (request == null) return;
    // The WebView can deliver the page's request after this view was
    // unmounted (the student navigated away while the lesson was still
    // loading); a defunct State has no `ref` (#28).
    if (!mounted) return;
    final generation = _generation;
    final result = await ref.read(lessonCodeRunnerProvider).run(request.code);
    if (!mounted || generation != _generation) return;
    await _controller.runJavaScript(lessonRunDeliverJs(request.id, result));
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
            Positioned.fill(child: ColoredBox(color: AppColors.ink0)),
        ],
      ),
    );
  }
}
