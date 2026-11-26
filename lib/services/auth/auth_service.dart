// Microsoft Entra ID auth via the OAuth 2.0 authorization code + PKCE flow,
// driven from the system browser.
//
// We rolled this by hand instead of depending on `aad_oauth` because the
// latter wraps `webview_flutter`, which has no Windows desktop platform
// implementation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/browser_launcher.dart';
import 'package:ai_tutor_python/services/auth/local_profile.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The handful of identity fields the rest of the app cares about. Computed
/// once per token issuance and cached in [AuthService] state.
@immutable
class AccountIdentity {
  const AccountIdentity({
    required this.oid,
    required this.displayName,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isTeacher,
  });

  /// Entra Object ID (GUID) — the partition key value across `accounts`,
  /// `progress`, `status_reports`.
  final String oid;
  final String displayName;
  final String email;
  final String firstName;
  final String lastName;
  final bool isTeacher;

  @override
  bool operator ==(Object other) =>
      other is AccountIdentity &&
      other.oid == oid &&
      other.displayName == displayName &&
      other.email == email &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.isTeacher == isTeacher;

  @override
  int get hashCode =>
      Object.hash(oid, displayName, email, firstName, lastName, isTeacher);
}

class AuthService extends Notifier<AccountIdentity?> {
  static const String _scope = 'openid profile email offline_access';

  /// Where the tokens are kept. Scoped per mode (#262); school mode keeps
  /// the key it always had, so existing installs stay signed in.
  static const String tokensPrefsKey = 'azure_auth_tokens_v1';
  String get _prefsKey =>
      ref.read(appModeProvider).scopedPrefsKey(tokensPrefsKey);

  /// The school to sign in with. Stand-alone mode has none (#264 gives it a
  /// local profile instead), so asking there is a bug.
  SchoolConfig get _school {
    final school = ref.read(appModeProvider).school;
    if (school == null) {
      throw StateError('Stand-alone mode has no school sign-in.');
    }
    return school;
  }

  String get _authorizeUrl =>
      'https://login.microsoftonline.com/${_school.tenantId}/oauth2/v2.0/authorize';
  String get _tokenUrl =>
      'https://login.microsoftonline.com/${_school.tenantId}/oauth2/v2.0/token';

  @override
  AccountIdentity? build() => null;

  /// The local profile's store; stand-alone mode only (#264).
  LocalProfileStore get _localProfiles {
    final mode = ref.read(appModeProvider);
    if (mode is! StandaloneMode) {
      throw StateError('School mode has no local profile.');
    }
    return LocalProfileStore(mode);
  }

  Future<void> tryAcquireTokenSilent() async {
    // Nothing to sign in to without a school: the local profile, if there is
    // one, is who uses the app (#264).
    if (ref.read(appModeProvider).school == null) {
      state = (await _localProfiles.load())?.toIdentity();
      return;
    }
    final stored = await _readStored();
    if (stored?.refreshToken == null) {
      state = null;
      return;
    }
    try {
      final refreshed = await _refreshTokens(stored!.refreshToken!);
      await _saveTokens(refreshed);
      _publishIdentity(refreshed.idToken);
    } catch (e, stack) {
      debugPrint('AuthService: silent refresh failed: $e\n$stack');
      await _clearStored();
      state = null;
    }
  }

  Future<void> signIn() async {
    final pkce = _generatePkce();
    final randomState = _randomString(32);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final boundRedirect = 'http://localhost:${server.port}/';
    try {
      final authUri = Uri.parse(_authorizeUrl).replace(
        queryParameters: {
          'client_id': _school.clientId,
          'response_type': 'code',
          'redirect_uri': boundRedirect,
          'response_mode': 'query',
          'scope': _scope,
          'state': randomState,
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'prompt': 'select_account',
        },
      );
      // The system browser, through the seam a test replaces (#345).
      final launched = await ref.read(browserLauncherProvider)(authUri);
      if (!launched) throw Exception('Could not launch the sign-in browser.');
      final code = await _awaitAuthorizationCode(
        server,
        expectedState: randomState,
      );
      final tokens = await _exchangeCodeForTokens(
        code: code,
        codeVerifier: pkce.verifier,
        redirectUri: boundRedirect,
      );
      await _saveTokens(tokens);
      _publishIdentity(tokens.idToken);
    } finally {
      await server.close(force: true);
    }
  }

  /// Stand-alone (#264): keeps [profile] as the one profile on this pc and
  /// makes it the identity. Also how a name change lands.
  Future<void> useLocalProfile(LocalProfile profile) async {
    await _localProfiles.save(profile);
    state = profile.toIdentity();
  }

  /// The stored local profile, or `null` (stand-alone only).
  Future<LocalProfile?> loadLocalProfile() => _localProfiles.load();

  Future<void> signOut() async {
    // Stand-alone has no sign-out (#264): dropping the profile would leave
    // its local data without an owner.
    if (ref.read(appModeProvider) is StandaloneMode) return;
    await _clearStored();
    state = null;
  }

  Future<String?> getAccessToken() async {
    final stored = await _readStored();
    if (stored == null) return null;
    final expiry = stored.accessTokenExpiry;
    if (stored.accessToken != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return stored.accessToken;
    }
    if (stored.refreshToken == null) return null;
    final refreshed = await _refreshTokens(stored.refreshToken!);
    await _saveTokens(refreshed);
    return refreshed.accessToken;
  }

  Future<String> _awaitAuthorizationCode(
    HttpServer server, {
    required String expectedState,
  }) async {
    final completer = Completer<String>();
    // The page the browser lands on after Entra redirects back. There is no
    // widget to localize it in, so it takes the app's resolved locale (#23).
    final l = ref.read(appLocalizationsProvider);
    late StreamSubscription<HttpRequest> sub;
    sub = server.listen((HttpRequest request) async {
      final params = request.uri.queryParameters;
      final returnedState = params['state'];
      final code = params['code'];
      final error = params['error'];
      final errorDesc = params['error_description'];
      request.response.headers.contentType = ContentType.html;
      if (error != null) {
        request.response.write(
          _browserBody(
            title: l.auth_browser_failed_title,
            body: errorDesc ?? error,
          ),
        );
      } else if (code == null) {
        request.response.write(
          _browserBody(
            title: l.auth_browser_failed_title,
            body: l.auth_browser_failed_noCode,
          ),
        );
      } else if (returnedState != expectedState) {
        request.response.write(
          _browserBody(
            title: l.auth_browser_failed_title,
            body: l.auth_browser_failed_stateMismatch,
          ),
        );
      } else {
        request.response.write(
          _browserBody(
            title: l.auth_browser_signedIn_title,
            body: l.auth_browser_signedIn_body,
          ),
        );
      }
      await request.response.close();
      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(
          Exception('Authorization failed: ${errorDesc ?? error}'),
        );
      } else if (code == null) {
        completer.completeError(Exception('No authorization code returned.'));
      } else if (returnedState != expectedState) {
        completer.completeError(Exception('State mismatch.'));
      } else {
        completer.complete(code);
      }
      await sub.cancel();
    });
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        sub.cancel();
        throw TimeoutException('Sign-in timed out.');
      },
    );
  }

  String _browserBody({required String title, required String body}) {
    final safeTitle = const HtmlEscape().convert(title);
    final safeBody = const HtmlEscape().convert(body);
    return '''
<!doctype html>
<html><head><meta charset="utf-8"><title>$safeTitle</title>
<style>
  body { font-family: system-ui, sans-serif; padding: 3rem; color: #222; }
  h1 { font-weight: 500; }
  p { color: #555; }
</style>
</head><body>
<h1>$safeTitle</h1>
<p>$safeBody</p>
</body></html>
''';
  }

  Future<_TokenSet> _exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _school.clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
        'scope': _scope,
      },
    );
    return _parseTokenResponse(response);
  }

  Future<_TokenSet> _refreshTokens(String refreshToken) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _school.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': _scope,
      },
    );
    return _parseTokenResponse(response);
  }

  _TokenSet _parseTokenResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception(
        'Entra token endpoint failed (${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    return _TokenSet(
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
      accessTokenExpiry: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn - 30)),
    );
  }

  void _publishIdentity(String? idToken) {
    if (idToken == null || idToken.isEmpty) {
      state = null;
      return;
    }
    state = _identityFromIdToken(idToken);
  }

  AccountIdentity? _identityFromIdToken(String jwt) {
    final claims = _decodeJwtPayload(jwt);
    if (claims == null) return null;
    final oid = claims['oid'] as String?;
    if (oid == null || oid.isEmpty) return null;
    final name = (claims['name'] as String?) ?? '';
    final email =
        (claims['email'] as String?) ??
        (claims['upn'] as String?) ??
        (claims['preferred_username'] as String?) ??
        '';
    String firstName = (claims['given_name'] as String?) ?? '';
    String lastName = (claims['family_name'] as String?) ?? '';
    if ((firstName.isEmpty || lastName.isEmpty) && name.isNotEmpty) {
      final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
      if (firstName.isEmpty && parts.isNotEmpty) firstName = parts.first;
      if (lastName.isEmpty && parts.length > 1) {
        lastName = parts.sublist(1).join(' ');
      }
    }
    final roles =
        (claims['roles'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return AccountIdentity(
      oid: oid,
      displayName: name,
      email: email,
      firstName: firstName,
      lastName: lastName,
      isTeacher: roles.contains('Teacher'),
    );
  }

  Map<String, dynamic>? _decodeJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final bytes = base64Url.decode(payload);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      debugPrint('AuthService: failed to decode id_token: $e');
      return null;
    }
  }

  Future<_TokenSet?> _readStored() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _TokenSet.fromStoredJson(json);
    } catch (e) {
      debugPrint('AuthService: failed to read stored tokens: $e');
      return null;
    }
  }

  Future<void> _saveTokens(_TokenSet tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(tokens.toStoredJson()));
  }

  Future<void> _clearStored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  _PkceCodes _generatePkce() {
    final verifier = _randomString(64);
    final hash = sha256.convert(utf8.encode(verifier));
    final challenge = base64Url.encode(hash.bytes).replaceAll('=', '');
    return _PkceCodes(verifier: verifier, challenge: challenge);
  }

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
  }
}

// ---------------------------------------------------------------------------
// Provider — defined here so any file that already imports auth_service.dart
// also gets the provider reference without an extra import.
// ---------------------------------------------------------------------------

final authServiceProvider = NotifierProvider<AuthService, AccountIdentity?>(
  AuthService.new,
);

final isTeacherProvider = Provider<bool>(
  (ref) => ref.watch(authServiceProvider)?.isTeacher ?? false,
);

/// Whether someone is signed in: changes on a sign-in and a sign-out, and on
/// nothing else about the identity.
///
/// A provider that lives as long as the app and polls the database watches
/// this, and polls only while it is `true` (#345): the polls stop at a
/// sign-out and start again at the next sign-in. With the database on the
/// sign-in (#306) a poll after the sign-out has no token to send, and with
/// the database key it would read for nobody. A provider that the screens
/// behind the sign-in hold (autoDispose, a widget's stream) stops with them.
final signedInProvider = Provider<bool>(
  (ref) =>
      ref.watch(authServiceProvider.select((identity) => identity != null)),
);

class _PkceCodes {
  const _PkceCodes({required this.verifier, required this.challenge});
  final String verifier;
  final String challenge;
}

class _TokenSet {
  const _TokenSet({
    this.accessToken,
    this.refreshToken,
    this.idToken,
    this.accessTokenExpiry,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime? accessTokenExpiry;

  Map<String, dynamic> toStoredJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'id_token': idToken,
    'access_token_expiry': accessTokenExpiry?.toUtc().toIso8601String(),
  };

  factory _TokenSet.fromStoredJson(Map<String, dynamic> json) {
    final raw = json['access_token_expiry'];
    return _TokenSet(
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
      accessTokenExpiry: raw is String ? DateTime.tryParse(raw) : null,
    );
  }
}
