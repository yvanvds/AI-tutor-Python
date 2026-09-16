// In-memory `WebViewPlatform` so widgets that host a `WebViewWidget`
// (LessonHtmlView) can be mounted in widget tests. Records every document
// loaded, every JavaScript channel registered and every script executed,
// and lets a test play the page's side of the bridge by posting a message
// on a channel — exactly what the real page does through
// `window.<channel>.postMessage(...)`.
//
// Also counts how often the platform *widget* is created and built (#128):
// every `WebViewWidget(...)` constructs one and every `WebViewWidget.build`
// builds it, and on Windows each such build re-mounts the native texture —
// so a host that keeps the lesson from blinking must keep both at one.

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakeWebViewController> controllers = [];

  /// How many platform widgets were created — one per `WebViewWidget(...)`
  /// constructor call.
  int widgetsCreated = 0;

  /// How many times any platform widget's `build` ran — one per
  /// `WebViewWidget.build`, i.e. per rebuild that reached the WebView.
  int widgetBuilds = 0;

  /// Installs a fresh fake as the global platform and returns it.
  static FakeWebViewPlatform install() {
    final platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    return platform;
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    widgetsCreated++;
    return FakeWebViewWidget(params, onBuild: () => widgetBuilds++);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  /// Every document handed to `loadHtmlString`, oldest first.
  final List<String> loadedHtml = [];

  /// Every script handed to `runJavaScript`, oldest first.
  final List<String> executedJs = [];

  final Map<String, JavaScriptChannelParams> channels = {};

  String get currentHtml => loadedHtml.last;

  /// Plays the page: posts [message] on [channel] as page JS would.
  void postMessage(String channel, String message) {
    final params = channels[channel];
    if (params == null) {
      throw StateError('no JavaScript channel "$channel" registered');
    }
    params.onMessageReceived(JavaScriptMessage(message: message));
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml.add(html);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    executedJs.add(javaScript);
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    channels.remove(javaScriptChannelName);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params, {required this.onBuild})
    : super.implementation();

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.expand();
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();
}
