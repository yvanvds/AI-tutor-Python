// Microsoft Entra ID auth via the OAuth 2.0 authorization code + PKCE flow,
// driven from the system browser (Step 3 of the Firebase → Azure migration).
//
// We rolled this by hand instead of depending on `aad_oauth` because the
// latter wraps `webview_flutter`, which has no Windows desktop platform
// implementation — the migration plan's third open question anticipated
// this and named the hand-rolled fallback as the path of last resort.
//
// Flow per sign-in:
//   1. Generate a PKCE code_verifier + code_challenge and a random state.
//   2. Open a `dart:io` HttpServer on a random localhost port to catch the
//      redirect.
//   3. Launch the Entra `/authorize` endpoint in the user's default browser.
//   4. Entra redirects to `http://localhost:<port>/?code=...&state=...`. The
//      local server captures the request, returns a small "you can close
//      this" page, and surfaces the code.
//   5. POST to `/token` with the code + verifier; we get back access /
//      refresh / id tokens.
//   6. Persist tokens in `shared_preferences` (per the school's "I don't
//      care about students tampering" stance — see the migration plan's
//      fifth open question).
//   7. Decode the id token JWT to populate `currentUser`.
//
// Silent refresh on subsequent launches uses the stored refresh_token + the
// `/token` endpoint's `grant_type=refresh_token` path; no browser involved.
//
// Entra app registration prerequisite: under "Authentication", add
// `http://localhost` (no port) as a redirect URI on the "Mobile and desktop
// applications" platform. Microsoft's loopback-redirect rules accept any
// port that matches that prefix. `AzureConfig.redirectUri` should be set to
// the same string.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_tutor_python/services/config/azure_config.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// The handful of identity fields the rest of the app cares about. Computed
/// once per token issuance and cached in `AuthService.currentUser`.
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

class AuthService {
  AuthService();

  /// `null` when signed out. Updated after silent refresh, interactive
  /// sign-in, or sign-out.
  final ValueNotifier<AccountIdentity?> currentUser =
      ValueNotifier<AccountIdentity?>(null);

  /// openid + profile + email yields name/given_name/family_name/email/upn
  /// claims on the id token. offline_access yields a refresh token so
  /// tryAcquireTokenSilent works on subsequent launches.
  static const String _scope = 'openid profile email offline_access';

  /// Single key under which we serialize the entire token bundle. v1 prefix
  /// gives us a cheap escape hatch if the shape ever changes.
  static const String _prefsKey = 'azure_auth_tokens_v1';

  String get _authorizeUrl =>
      'https://login.microsoftonline.com/${AzureConfig.tenantId}/oauth2/v2.0/authorize';
  String get _tokenUrl =>
      'https://login.microsoftonline.com/${AzureConfig.tenantId}/oauth2/v2.0/token';

  // ---------------------------------------------------------------------- //
  //  Public API                                                            //
  // ---------------------------------------------------------------------- //

  /// Called once at app boot. If a refresh token is cached, populates
  /// `currentUser` before the first frame renders so a returning user lands
  /// directly on HomeShell instead of flashing the sign-in page.
  Future<void> tryAcquireTokenSilent() async {
    final stored = await _readStored();
    if (stored?.refreshToken == null) {
      currentUser.value = null;
      return;
    }
    try {
      final refreshed = await _refreshTokens(stored!.refreshToken!);
      await _saveTokens(refreshed);
      _publishIdentity(refreshed.idToken);
    } catch (e, stack) {
      debugPrint('AuthService: silent refresh failed: $e\n$stack');
      await _clearStored();
      currentUser.value = null;
    }
  }

  /// Interactive sign-in. Opens the system browser, runs a localhost
  /// redirect catcher, exchanges the code for tokens. Throws on failure so
  /// the sign-in page can render the error.
  Future<void> signIn() async {
    final pkce = _generatePkce();
    final state = _randomString(32);

    // Bind the redirect listener BEFORE opening the browser so we know our
    // port and can include it verbatim in the redirect_uri.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final boundRedirect = 'http://localhost:${server.port}/';

    try {
      final authUri = Uri.parse(_authorizeUrl).replace(
        queryParameters: {
          'client_id': AzureConfig.clientId,
          'response_type': 'code',
          'redirect_uri': boundRedirect,
          'response_mode': 'query',
          'scope': _scope,
          'state': state,
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'prompt': 'select_account',
        },
      );

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Could not launch the sign-in browser.');
      }

      final code = await _awaitAuthorizationCode(server, expectedState: state);
      final tokens = await _exchangeCodeForTokens(
        code: code,
        codeVerifier: pkce.verifier,
        redirectUri: boundRedirect,
      );
      await _saveTokens(tokens);
      _publishIdentity(tokens.idToken);
    } finally {
      // Always release the port, even if the user cancelled mid-flow.
      await server.close(force: true);
    }
  }

  Future<void> signOut() async {
    await _clearStored();
    currentUser.value = null;
  }

  /// Returns a valid access token, refreshing if necessary. Step 3 doesn't
  /// use this — Cosmos auth is master-key for now — but exposing it keeps a
  /// future AAD-RBAC swap to a one-line change in `cosmos_client`.
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

  void dispose() {
    currentUser.dispose();
  }

  // ---------------------------------------------------------------------- //
  //  Browser ↔ localhost redirect plumbing                                  //
  // ---------------------------------------------------------------------- //

  Future<String> _awaitAuthorizationCode(
    HttpServer server, {
    required String expectedState,
  }) async {
    final completer = Completer<String>();
    late StreamSubscription<HttpRequest> sub;

    sub = server.listen((HttpRequest request) async {
      final params = request.uri.queryParameters;
      final returnedState = params['state'];
      final code = params['code'];
      final error = params['error'];
      final errorDesc = params['error_description'];

      // Always close the HTTP response promptly so the browser tab shows our
      // friendly message instead of spinning.
      request.response.headers.contentType = ContentType.html;
      if (error != null) {
        request.response.write(_browserBody(
          title: 'Sign-in failed',
          body: errorDesc ?? error,
        ));
      } else if (code == null) {
        request.response.write(_browserBody(
          title: 'Sign-in failed',
          body: 'No authorization code returned.',
        ));
      } else if (returnedState != expectedState) {
        request.response.write(_browserBody(
          title: 'Sign-in failed',
          body: 'State mismatch — possible CSRF, please try again.',
        ));
      } else {
        request.response.write(_browserBody(
          title: 'Signed in',
          body: 'You can close this tab and return to the app.',
        ));
      }
      await request.response.close();

      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(
          Exception('Authorization failed: ${errorDesc ?? error}'),
        );
      } else if (code == null) {
        completer.completeError(
          Exception('No authorization code returned.'),
        );
      } else if (returnedState != expectedState) {
        completer.completeError(Exception('State mismatch.'));
      } else {
        completer.complete(code);
      }
      await sub.cancel();
    });

    // Five-minute window covers slow logins / MFA prompts; longer than that
    // and the user has wandered off.
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

  // ---------------------------------------------------------------------- //
  //  Token endpoint calls                                                  //
  // ---------------------------------------------------------------------- //

  Future<_TokenSet> _exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': AzureConfig.clientId,
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
        'client_id': AzureConfig.clientId,
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
        'Entra token endpoint failed (${response.statusCode}): '
        '${response.body}',
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

  // ---------------------------------------------------------------------- //
  //  Identity extraction (id_token JWT)                                    //
  // ---------------------------------------------------------------------- //

  void _publishIdentity(String? idToken) {
    if (idToken == null || idToken.isEmpty) {
      currentUser.value = null;
      return;
    }
    currentUser.value = _identityFromIdToken(idToken);
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
    final isTeacher = roles.contains('Teacher');

    return AccountIdentity(
      oid: oid,
      displayName: name,
      email: email,
      firstName: firstName,
      lastName: lastName,
      isTeacher: isTeacher,
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

  // ---------------------------------------------------------------------- //
  //  Token persistence                                                      //
  // ---------------------------------------------------------------------- //

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

  // ---------------------------------------------------------------------- //
  //  PKCE helpers                                                          //
  // ---------------------------------------------------------------------- //

  _PkceCodes _generatePkce() {
    final verifier = _randomString(64);
    final hash = sha256.convert(utf8.encode(verifier));
    final challenge = base64Url.encode(hash.bytes).replaceAll('=', '');
    return _PkceCodes(verifier: verifier, challenge: challenge);
  }

  String _randomString(int length) {
    // RFC 7636 unreserved chars only — Entra rejects others in code_verifier.
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List<String>.generate(length, (_) => chars[r.nextInt(chars.length)])
        .join();
  }
}

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
