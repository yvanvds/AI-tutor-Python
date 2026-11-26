// Database access with the user's own Entra sign-in (#306).
//
// A school whose school file says `"databaseAccess": "signIn"`, and every
// school in a build without school data (#336), reaches its database with
// an access token for the database account
// (`https://<account>.documents.azure.com/user_impersonation`), not with a
// database key. The token comes silently from the refresh token the sign-in
// stored (`AuthService`); the user signs in once, as before.
//
// The token lives in memory only. It is renewed a few minutes before it
// expires, and `AadTokenAuth` (lib/core/cosmos_client.dart) asks for a fresh
// one once when the database answers 401 anyway.

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// How long before its expiry a token is renewed.
const Duration kCosmosTokenRenewMargin = Duration(minutes: 5);

/// Hands out access tokens for one school's database account.
class CosmosTokenSource {
  CosmosTokenSource({
    required this._school,
    required String tokensPrefsKey,
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _prefsKey = tokensPrefsKey,
       _http = httpClient,
       _now = now ?? DateTime.now;

  /// The source for [mode]'s school, reading the sign-in where `AuthService`
  /// keeps it. [httpClient] reaches the token endpoint; `null` (production)
  /// opens its own connections.
  factory CosmosTokenSource.forMode(
    SchoolMode mode, {
    http.Client? httpClient,
  }) => CosmosTokenSource(
    school: mode.school,
    tokensPrefsKey: mode.scopedPrefsKey(AuthService.tokensPrefsKey),
    httpClient: httpClient,
  );

  final SchoolConfig _school;
  final String _prefsKey;
  final http.Client? _http;
  final DateTime Function() _now;

  _CachedToken? _cached;
  Future<String>? _pending;

  /// The scope of the database account behind [endpoint]: its origin
  /// without a port, then `/user_impersonation`.
  static String scopeFor(Uri endpoint) =>
      '${endpoint.scheme}://${endpoint.host}/user_impersonation';

  Uri get _tokenUrl => Uri.parse(
    'https://login.microsoftonline.com/${_school.tenantId}/oauth2/v2.0/token',
  );

  /// An access token for the database. The cached one while it is valid
  /// for more than [kCosmosTokenRenewMargin] and belongs to the sign-in
  /// stored now; otherwise, or with [forceRefresh], a new one.
  ///
  /// Throws a 401 [CosmosException] when nobody is signed in or the sign-in
  /// cannot give a token, so callers treat it like the database refusing.
  Future<String> token({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = _readStored(prefs);
    final refreshToken = stored?['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      _cached = null;
      throw CosmosException(
        401,
        'Not signed in: no sign-in to get a database token from.',
        code: 'NotSignedIn',
      );
    }
    final cached = _cached;
    if (!forceRefresh &&
        cached != null &&
        cached.refreshToken == refreshToken &&
        cached.expiry.isAfter(_now().add(kCosmosTokenRenewMargin))) {
      return cached.accessToken;
    }
    // Requests that need a token at the same moment share one renewal.
    return _pending ??= _renew(prefs, refreshToken).whenComplete(() {
      _pending = null;
    });
  }

  Future<String> _renew(SharedPreferences prefs, String refreshToken) async {
    final body = {
      'client_id': _school.clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': '${scopeFor(_school.databaseEndpoint)} offline_access',
    };
    const headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    final http.Response response;
    try {
      final client = _http;
      response = client == null
          ? await http.post(_tokenUrl, headers: headers, body: body)
          : await client.post(_tokenUrl, headers: headers, body: body);
    } on Object catch (e) {
      throw CosmosException(
        kCosmosNetworkStatus,
        'No response from the sign-in service: $e',
        code: 'NetworkError',
      );
    }
    if (response.statusCode != 200) {
      debugPrint(
        'CosmosTokenSource: token request failed '
        '(${response.statusCode}): ${response.body}',
      );
      // 5xx: the sign-in service had a problem, worth trying again later.
      // Anything else: the sign-in cannot give this token.
      throw CosmosException(
        response.statusCode >= 500 ? response.statusCode : 401,
        'The sign-in gave no database token (${response.statusCode}).',
        code: 'TokenRequestFailed',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = json['access_token'];
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    if (accessToken is! String || accessToken.isEmpty || expiresIn == null) {
      throw CosmosException(
        401,
        'The sign-in service answered without a database token.',
        code: 'TokenRequestFailed',
      );
    }
    // A rotated refresh token goes back where the sign-in keeps it, but
    // only while that is still the sign-in this token came from: a sign-out
    // or a new sign-in in the meantime wins.
    var usedRefreshToken = refreshToken;
    final rotated = json['refresh_token'];
    if (rotated is String && rotated.isNotEmpty && rotated != refreshToken) {
      final now = _readStored(prefs);
      if (now != null && now['refresh_token'] == refreshToken) {
        now['refresh_token'] = rotated;
        await prefs.setString(_prefsKey, jsonEncode(now));
        usedRefreshToken = rotated;
      }
    }
    _cached = _CachedToken(
      accessToken: accessToken,
      refreshToken: usedRefreshToken,
      expiry: _now().add(Duration(seconds: expiresIn)),
    );
    return accessToken;
  }

  Map<String, dynamic>? _readStored(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

class _CachedToken {
  const _CachedToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
  });

  final String accessToken;

  /// The refresh token stored with it; another one means another sign-in.
  final String refreshToken;
  final DateTime expiry;
}
