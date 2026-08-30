/// Where a published release is looked up (#50): GitHub's Releases API,
/// instead of the `version.json` manifest `build_release.ps1` used to write
/// and GitHub Pages used to serve.
///
/// The manifest was a second artifact that had to stay in lockstep with the
/// release it described, and that lockstep had already broken once — as a
/// BOM that made the manifest unparseable (#45). A release published by hand
/// through the GitHub UI was invisible to the app entirely. Here the release
/// *is* the manifest: the tag carries the version, the assets carry the
/// installer and its checksum, and there is nothing left to keep in sync.
///
/// The repository is public, so the feed is queried **unauthenticated**: no
/// token has to sit on a student's machine, and the anonymous rate limit (60
/// requests per hour per IP) is far above one check per launch.
///
/// This file parses and fetches; it decides nothing. `update_controller.dart`
/// turns the result into state, and `update_bootstrap.dart` wires it up.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_info.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

/// The repository releases are published to.
const String kReleaseOwner = 'yvanvds';
const String kReleaseRepo = 'AI-tutor-Python';

/// The installer asset, named as `tooling/build_release.ps1` uploads it.
const String kInstallerAssetName = 'python_teacher_install.exe';

/// The installer's checksum, uploaded beside it as a second asset.
///
/// The Releases API exposes no hash of its own, and the alternative —
/// trusting TLS to github.com and running whatever comes back — would quietly
/// drop the one guarantee the manifest did give us. One extra request keeps
/// it (see [UpdateInfo.sha256] and `verifyAndCleanUp`).
const String kChecksumAssetName = '$kInstallerAssetName.sha256';

/// GitHub's "latest release" for this repository.
///
/// `/releases/latest` already excludes drafts and pre-releases, which is the
/// behaviour wanted here — tagging a pre-release must not push it at every
/// student — so no filtering of our own is needed.
final Uri kLatestReleaseEndpoint = Uri.https(
  'api.github.com',
  '/repos/$kReleaseOwner/$kReleaseRepo/releases/latest',
);

/// What the API wants to be asked with: the documented media type, and a
/// pinned API version so a future default cannot reshape the payload under a
/// build that has already shipped.
const Map<String, String> kGitHubApiHeaders = <String, String>{
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
};

/// A leading byte-order mark. `jsonDecode` does not skip it, and neither does
/// a hash comparison (#45).
const String _bom = '\u{FEFF}';

/// One published release, as far as this app cares: the version it carries,
/// the installer to run, and the checksum to check it against.
class PublishedRelease {
  const PublishedRelease({
    required this.version,
    required this.installerUrl,
    required this.checksumUrl,
    this.notes = '',
    this.pageUrl = '',
  });

  /// The tag's version, with a leading `v` already gone — `2.0.0+18`.
  final String version;

  /// Where the Windows installer for [version] is downloaded from.
  final Uri installerUrl;

  /// Where its `.sha256` is downloaded from, or `null` when the release does
  /// not publish one. A release that cannot be verified is not one to
  /// install silently, so [fetchLatestRelease] reports that as a failure
  /// rather than offering it.
  final Uri? checksumUrl;

  /// The release notes, as written on the GitHub release. Something the
  /// manifest could not carry; the offer UI shows it (#48).
  final String notes;

  /// The release's own page, for a reader who would rather see it there.
  final String pageUrl;
}

/// Parses a release tag (`v2.0.0+18`, or a bare `2.0.0+18`) into the version
/// string the rest of the updater compares with [isNewer].
///
/// Returns `null` rather than throwing on anything that is not a version: a
/// tag somebody pushed by hand must not be able to crash a launch-time check.
String? parseReleaseTag(String tag) {
  final String trimmed = tag.trim();
  final String bare = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  try {
    Version.parse(bare);
  } on FormatException {
    return null;
  }
  return bare;
}

String _assetName(Map<String, dynamic> asset) {
  final Object? name = asset['name'];
  return name is String ? name : '';
}

Uri? _assetUrl(Map<String, dynamic> asset) {
  final Object? url = asset['browser_download_url'];
  if (url is! String) return null;
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  return uri;
}

Uri? _firstNamed(List<Map<String, dynamic>> assets, String name) {
  for (final Map<String, dynamic> asset in assets) {
    if (_assetName(asset) == name) {
      final Uri? url = _assetUrl(asset);
      if (url != null) return url;
    }
  }
  return null;
}

/// Picks the Windows installer out of a release's asset list.
///
/// Prefers the asset the release script uploads ([kInstallerAssetName]) and
/// falls back to a *lone* `.exe`, so a release published by hand under a
/// different name is still offerable — but several `.exe` assets are left
/// alone rather than guessed at. Returns `null` when the release carries no
/// installer, which is "nothing to offer", not a failure.
Map<String, dynamic>? installerAsset(List<Map<String, dynamic>> assets) {
  for (final Map<String, dynamic> asset in assets) {
    if (_assetName(asset) == kInstallerAssetName && _assetUrl(asset) != null) {
      return asset;
    }
  }
  final List<Map<String, dynamic>> exes = assets
      .where(
        (a) =>
            _assetName(a).toLowerCase().endsWith('.exe') &&
            _assetUrl(a) != null,
      )
      .toList();
  return exes.length == 1 ? exes.single : null;
}

/// Reads a `/releases/latest` payload into a [PublishedRelease].
///
/// Returns `null` for anything that is not a release this app can offer: a
/// payload that is not an object, a missing or unparseable tag, or no
/// installer asset. Split from the HTTP call so the parsing is unit-testable
/// against a captured payload.
PublishedRelease? releaseFromJson(Object? json) {
  if (json is! Map) return null;
  final Object? tag = json['tag_name'];
  if (tag is! String) return null;
  final String? version = parseReleaseTag(tag);
  if (version == null) return null;

  final Object? rawAssets = json['assets'];
  final List<Map<String, dynamic>> assets = rawAssets is List
      ? rawAssets.whereType<Map<String, dynamic>>().toList()
      : const <Map<String, dynamic>>[];

  final Map<String, dynamic>? installer = installerAsset(assets);
  if (installer == null) return null;

  final String checksumName = '${_assetName(installer)}.sha256';
  return PublishedRelease(
    version: version,
    installerUrl: _assetUrl(installer)!,
    checksumUrl:
        _firstNamed(assets, checksumName) ??
        _firstNamed(assets, kChecksumAssetName),
    notes: json['body'] is String ? json['body'] as String : '',
    pageUrl: json['html_url'] is String ? json['html_url'] as String : '',
  );
}

/// Hex digits of a SHA-256, and nothing else.
final RegExp _sha256Hex = RegExp(r'^[0-9a-fA-F]{64}$');

/// Reads the checksum asset: a bare hash, or the `sha256sum` shape
/// (`<hash>  <filename>`) that `build_release.ps1` writes.
///
/// Returns `null` when the body is not a checksum at all — an HTML error
/// page, an empty file, a truncated hash. A leading BOM is tolerated (#45).
String? parseSha256Document(String body) {
  final String text = body.startsWith(_bom)
      ? body.substring(_bom.length)
      : body;
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final String token = trimmed.split(RegExp(r'\s')).first;
  if (!_sha256Hex.hasMatch(token)) return null;
  return token.toLowerCase();
}

/// Fetches the latest published release from the GitHub Releases API.
///
/// Returns `null` when there is nothing to offer — the repository has no
/// release (HTTP 404), the tag is not a version, or the release carries no
/// installer. Throws an [UpdateCheckException] for everything else: a
/// timeout, a transport error, any other non-200 (rate limiting included), a
/// payload that is not JSON, or a release that publishes an installer with no
/// checksum beside it. That distinction is #46's and is what keeps a broken
/// check from reading as "you are up to date".
Future<UpdateInfo?> fetchLatestRelease(
  Uri endpoint, {
  http.Client? client,
  Duration timeout = kUpdateRequestTimeout,
}) async {
  final bool owned = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final http.Response res = await _get(
      c,
      endpoint,
      headers: kGitHubApiHeaders,
      timeout: timeout,
    );

    // Nothing published yet — a normal outcome, not a failure.
    if (res.statusCode == HttpStatus.notFound) return null;
    if (res.statusCode != HttpStatus.ok) {
      throw UpdateCheckException(
        'release lookup at $endpoint returned HTTP ${res.statusCode}'
        '${_rateLimitHint(res)}',
      );
    }

    final Object? decoded;
    try {
      // Decode the bytes as UTF-8 rather than reading `res.body`: that getter
      // honours the response charset and falls back to latin1 for a type like
      // `application/octet-stream`, which is exactly what a release *asset*
      // is served as (#45). JSON is UTF-8 (RFC 8259).
      decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } on FormatException {
      throw UpdateCheckException('$endpoint did not answer with JSON');
    }

    final PublishedRelease? release = releaseFromJson(decoded);
    // No installer, or a tag nobody can compare: nothing to offer, and
    // nothing wrong either.
    if (release == null) return null;

    final Uri? checksumUrl = release.checksumUrl;
    if (checksumUrl == null) {
      throw UpdateCheckException(
        'release ${release.version} publishes an installer but no '
        '$kChecksumAssetName, so nothing can verify the download',
      );
    }

    return UpdateInfo(
      release.version,
      release.installerUrl,
      await _fetchChecksum(c, checksumUrl, timeout),
      notes: release.notes,
    );
  } finally {
    // Closing an owned client also aborts a request still in flight after a
    // timeout fired.
    if (owned) c.close();
  }
}

/// Downloads the `.sha256` asset and reads the hash out of it.
Future<String> _fetchChecksum(
  http.Client client,
  Uri url,
  Duration timeout,
) async {
  final http.Response res = await _get(client, url, timeout: timeout);
  if (res.statusCode != HttpStatus.ok) {
    throw UpdateCheckException(
      'checksum download from $url returned HTTP ${res.statusCode}',
    );
  }
  // Release assets come back as `application/octet-stream`, so `res.body`
  // would latin1-decode them (#45).
  final String? sha = parseSha256Document(
    utf8.decode(res.bodyBytes, allowMalformed: true),
  );
  if (sha == null) {
    throw UpdateCheckException('$url is not a sha256 checksum');
  }
  return sha;
}

/// A bounded GET that reports its failures as [UpdateCheckException].
Future<http.Response> _get(
  http.Client client,
  Uri url, {
  Map<String, String> headers = const <String, String>{},
  required Duration timeout,
}) async {
  try {
    return await client.get(url, headers: headers).timeout(timeout);
  } on TimeoutException {
    throw UpdateCheckException(
      'request to $url timed out after ${timeout.inSeconds}s',
    );
  } on UpdateCheckException {
    rethrow;
  } on Object catch (e) {
    throw UpdateCheckException('request to $url failed: $e');
  }
}

/// GitHub answers a spent rate limit with a 403 or a 429 and
/// `x-ratelimit-remaining: 0`. Saying so beats "HTTP 403" on its own in the
/// About panel (#48), because it is the one failure here that fixes itself.
String _rateLimitHint(http.Response res) {
  final String? remaining = res.headers['x-ratelimit-remaining'];
  if (remaining != '0') return '';
  return ' (the GitHub API rate limit for this network is used up; '
      'it resets within the hour)';
}
