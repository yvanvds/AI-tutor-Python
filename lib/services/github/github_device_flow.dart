/// GitHub's OAuth **device flow** (#57), the way a student connects the app
/// to GitHub before filing a bug report.
///
/// It replaces the personal access token a student used to paste in (#25).
/// A PAT meant sending a fourteen-year-old to github.com/settings/tokens to
/// pick scopes and an expiry, then trusting them to paste the one string they
/// must never paste anywhere else. The device flow asks for none of that: the
/// app shows a short code, the student approves it in a browser they are
/// already signed into, and the app receives a token it never has to explain.
///
/// The flow needs **no client secret** — that is exactly why it fits a
/// desktop app that ships to students, where any secret compiled into the
/// binary is a secret handed out with the binary. All it needs is the public
/// client id in [GitHubOAuthConfig], which a build may legitimately not have
/// (see [GitHubDeviceFlow.isConfigured]).
///
/// The two requests, per GitHub's documentation:
///
///   1. `POST https://github.com/login/device/code` → a `device_code` the app
///      keeps, a `user_code` the student types, a `verification_uri` to type
///      it at, and the `interval` / `expires_in` that bound the polling.
///   2. `POST https://github.com/login/oauth/access_token`, repeatedly, until
///      it answers with an `access_token` instead of `authorization_pending`.
///
/// HTTP conventions here follow `core/github_release.dart`: an injectable
/// client, a bounded timeout on every request, and `bodyBytes` decoded as
/// UTF-8 explicitly rather than through `res.body`, whose charset guess is
/// wrong for anything not served as `application/json`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/github/github_oauth_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// The one scope the app asks for.
///
/// `public_repo` is the narrowest OAuth scope that can create an issue on
/// `yvanvds/AI-tutor-Python`. There is no issues-only scope in the OAuth-app
/// model — that granularity exists only for GitHub Apps and fine-grained
/// PATs, neither of which supports the device flow the same way — and the
/// empty scope grants read-only access to public data, which cannot post
/// anything. `repo` would have worked too and is what most examples show; it
/// is deliberately *not* used, because it would also hand this app write
/// access to every private repository the student can see.
const String kGitHubOAuthScope = 'public_repo';

/// Where the device flow lives. Not `api.github.com`: the OAuth endpoints sit
/// on the website host.
final Uri kGitHubOAuthBase = Uri.parse('https://github.com/');

/// Bounds a single request. The *flow* is allowed to take a quarter of an
/// hour (that is the student walking to a browser); one HTTP round trip is
/// not.
const Duration kDeviceFlowRequestTimeout = Duration(seconds: 20);

/// What GitHub falls back to when it does not say otherwise.
const Duration _defaultInterval = Duration(seconds: 5);
const Duration _defaultExpiry = Duration(minutes: 15);

/// How much slower to poll when GitHub answers `slow_down` without naming a
/// new interval. Five seconds is the increment its documentation describes.
const Duration _slowDownStep = Duration(seconds: 5);

/// Why a device flow ended without a token. Each one reads differently to a
/// student, so the UI branches on this rather than on a message.
enum DeviceFlowFailure {
  /// This build carries no OAuth client id, so there is no flow to start.
  notConfigured,

  /// The student declined the request in the browser.
  denied,

  /// The user code went stale before anyone approved it.
  expired,

  /// The student pressed Cancel in the app.
  cancelled,

  /// A network error, or anything GitHub said that is not one of the above.
  failed,
}

class DeviceFlowException implements Exception {
  const DeviceFlowException(this.reason, this.message);

  final DeviceFlowFailure reason;
  final String message;

  @override
  String toString() => message;
}

/// The half of the flow the student can see: the code to type and where to
/// type it, plus the timing GitHub asked the app to respect.
class DeviceCodeGrant {
  const DeviceCodeGrant({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.interval = _defaultInterval,
    this.expiresIn = _defaultExpiry,
  });

  /// The app's half of the pair. Never shown — it is the secret that lets
  /// this process, and no other, claim the approved token.
  final String deviceCode;

  /// The student's half: eight characters like `WDJB-MJHT`.
  final String userCode;

  /// Where to type it — `https://github.com/login/device`.
  final Uri verificationUri;

  /// How long to wait between polls. Polling faster earns a `slow_down`.
  final Duration interval;

  /// How long [userCode] stays valid.
  final Duration expiresIn;
}

class GitHubDeviceFlow {
  GitHubDeviceFlow({
    required this.clientId,
    http.Client? client,
    Uri? authBase,
    this.timeout = kDeviceFlowRequestTimeout,
    Future<void> Function(Duration)? wait,
  }) : _client = client ?? http.Client(),
       _authBase = authBase ?? kGitHubOAuthBase,
       _wait = wait ?? _realWait;

  static Future<void> _realWait(Duration d) => Future<void>.delayed(d);

  /// The public client id of the OAuth app requests are made on behalf of.
  final String clientId;

  final http.Client _client;
  final Uri _authBase;
  final Duration timeout;

  /// The pause between polls, as a seam: a test drives the whole loop without
  /// spending the seconds GitHub would make it spend.
  final Future<void> Function(Duration) _wait;

  /// Whether this build can run the flow at all.
  ///
  /// False when no OAuth app has been registered for it — a fork that has not
  /// done the setup, or a checkout whose `.env` predates the feature. Callers
  /// are expected to say so in the UI rather than start a flow that can only
  /// end in `unauthorized_client`.
  bool get isConfigured => clientId.isNotEmpty;

  Uri get _deviceCodeEndpoint => _authBase.resolve('/login/device/code');
  Uri get _accessTokenEndpoint =>
      _authBase.resolve('/login/oauth/access_token');

  /// Step 1: asks GitHub for a code pair the student can approve.
  Future<DeviceCodeGrant> requestCode() async {
    if (!isConfigured) {
      throw const DeviceFlowException(
        DeviceFlowFailure.notConfigured,
        'This build has no GitHub OAuth client id.',
      );
    }
    final Map<String, dynamic> json = await _post(_deviceCodeEndpoint, {
      'client_id': clientId,
      'scope': kGitHubOAuthScope,
    });
    if (json['error'] != null) {
      throw DeviceFlowException(DeviceFlowFailure.failed, _describe(json));
    }

    final Object? deviceCode = json['device_code'];
    final Object? userCode = json['user_code'];
    final Uri? verificationUri = _uri(json['verification_uri']);
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        verificationUri == null) {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        '$_deviceCodeEndpoint did not answer with a device code.',
      );
    }

    return DeviceCodeGrant(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      interval: _seconds(json['interval']) ?? _defaultInterval,
      expiresIn: _seconds(json['expires_in']) ?? _defaultExpiry,
    );
  }

  /// Step 2: polls until the student approves [grant], and returns the token.
  ///
  /// Honours the interval GitHub asked for and backs off further on
  /// `slow_down`; gives up on `expired_token`, on `access_denied`, and on its
  /// own once [DeviceCodeGrant.expiresIn] has passed — GitHub is not obliged
  /// to volunteer the expiry, and a loop that polls a dead code forever is
  /// the one failure mode a student would never see the end of.
  ///
  /// [isCancelled] is checked around every wait, so the Cancel button in the
  /// UI stops the loop within one interval rather than at the next answer.
  Future<String> pollForToken(
    DeviceCodeGrant grant, {
    bool Function()? isCancelled,
  }) async {
    Duration interval = grant.interval;
    Duration elapsed = Duration.zero;

    while (true) {
      if (isCancelled?.call() ?? false) throw _cancelled;
      await _wait(interval);
      elapsed += interval;
      if (isCancelled?.call() ?? false) throw _cancelled;
      if (elapsed >= grant.expiresIn) throw _expired;

      final Map<String, dynamic> json = await _post(_accessTokenEndpoint, {
        'client_id': clientId,
        'device_code': grant.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });

      final Object? token = json['access_token'];
      if (token is String && token.isNotEmpty) return token;

      final Object? error = json['error'];
      if (error == 'authorization_pending') {
        // Nobody has approved it yet; that is the normal answer.
      } else if (error == 'slow_down') {
        interval = _seconds(json['interval']) ?? (interval + _slowDownStep);
      } else if (error == 'expired_token') {
        throw _expired;
      } else if (error == 'access_denied') {
        throw _denied;
      } else {
        throw DeviceFlowException(DeviceFlowFailure.failed, _describe(json));
      }
    }
  }

  static const DeviceFlowException _expired = DeviceFlowException(
    DeviceFlowFailure.expired,
    'The device code expired before it was approved.',
  );

  static const DeviceFlowException _cancelled = DeviceFlowException(
    DeviceFlowFailure.cancelled,
    'The sign-in was cancelled.',
  );

  static const DeviceFlowException _denied = DeviceFlowException(
    DeviceFlowFailure.denied,
    'The request was declined on GitHub.',
  );

  /// Both endpoints are form-encoded POSTs that answer with JSON once asked
  /// to. GitHub reports flow errors with HTTP 200 and an `error` field, while
  /// RFC 8628 uses 400 for the same thing — both are read as a body here, and
  /// only the caller decides which errors are fatal.
  Future<Map<String, dynamic>> _post(Uri url, Map<String, String> body) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            url,
            headers: const <String, String>{'Accept': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        'request to $url timed out after ${timeout.inSeconds}s',
      );
    } on Object catch (e) {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        'request to $url failed: $e',
      );
    }

    if (res.statusCode != HttpStatus.ok &&
        res.statusCode != HttpStatus.badRequest) {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        '$url returned HTTP ${res.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        '$url did not answer with JSON',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw DeviceFlowException(
        DeviceFlowFailure.failed,
        '$url did not answer with a JSON object',
      );
    }
    return decoded;
  }

  /// The most human sentence in an OAuth error payload.
  static String _describe(Map<String, dynamic> json) {
    final Object? description = json['error_description'];
    if (description is String && description.isNotEmpty) return description;
    final Object? error = json['error'];
    if (error is String && error.isNotEmpty) return error;
    return 'GitHub refused the request.';
  }

  /// GitHub sends these as numbers, but a JSON payload is not something to
  /// take on trust; anything else means "use the default".
  static Duration? _seconds(Object? value) {
    if (value is int && value > 0) return Duration(seconds: value);
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return Duration(seconds: parsed);
    }
    return null;
  }

  static Uri? _uri(Object? value) {
    if (value is! String) return null;
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return uri;
  }
}

/// The OAuth app this build signs in as — empty when none was registered for
/// it (see `github_oauth_config.dart` and README "Step 8").
final gitHubOAuthClientIdProvider = Provider<String>(
  (_) => GitHubOAuthConfig.clientId,
);

/// Where the OAuth endpoints live. A seam so an end-to-end flow can point the
/// real client at a loopback server instead of github.com.
final gitHubOAuthBaseProvider = Provider<Uri>((_) => kGitHubOAuthBase);

final gitHubDeviceFlowProvider = Provider<GitHubDeviceFlow>(
  (ref) => GitHubDeviceFlow(
    clientId: ref.watch(gitHubOAuthClientIdProvider),
    authBase: ref.watch(gitHubOAuthBaseProvider),
  ),
);

/// Opening the student's browser at the verification URL.
///
/// A seam for the same reason `installerLauncherProvider` is one (#49): the
/// production implementation hands a URL to the operating system, which in a
/// test run means a real browser window on the machine running the suite.
typedef BrowserLauncher = Future<bool> Function(Uri url);

final browserLauncherProvider = Provider<BrowserLauncher>(
  (_) =>
      (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
