// Issue #55 — the installer must register the version that was actually built.
//
// `windows/packaging/exe/installer.iss` used to carry `#define AppVersion
// "1.0.1"` and nothing ever rewrote it, so every installer ever produced told
// Windows it was 1.0.1: that string is what Apps & Features and the uninstall
// key's `DisplayVersion` show, and only the app's own About panel told the
// truth. The fix moves the version to a `/D` define that
// `tooling/build_release.ps1` passes to ISCC after it bumps pubspec.yaml.
//
// There is no app-level test for this: nothing about it is reachable from the
// running app (the About panel already reported the right version — the bug was
// entirely in what the installer wrote to the registry), and compiling the .iss
// needs Inno Setup plus a finished ~250 MB release build. So the two halves of
// the contract are asserted here instead, against the real files: the .iss
// takes the version from outside and the release script hands it in.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing (cwd: ${Directory.current})');
  }
  // Normalise line endings: these files are LF in the repo but a Windows CI
  // checkout (core.autocrlf) hands them over as CRLF, and a stray \r would
  // break every `$`-anchored match below.
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  final iss = _read('windows/packaging/exe/installer.iss');
  final script = _read('tooling/build_release.ps1');
  final pubspec = _read('pubspec.yaml');

  group('installer.iss takes its version from the command line', () {
    test('AppVersion is only defined as a guarded 0.0.0 fallback', () {
      final defines = RegExp(
        r'^\s*#define\s+AppVersion\s+"([^"]*)"',
        multiLine: true,
      ).allMatches(iss).map((m) => m.group(1)).toList();

      expect(
        defines,
        ['0.0.0'],
        reason:
            'A hardcoded AppVersion is the #55 bug: it is never bumped, so '
            'every release installs as that version. Pass it in with '
            '/DAppVersion= instead.',
      );
      expect(
        iss,
        contains('#ifndef AppVersion'),
        reason:
            'The fallback must be #ifndef-guarded or /D cannot override it.',
      );
    });

    test('AppVersionInfo is only defined as a guarded 0.0.0.0 fallback', () {
      final defines = RegExp(
        r'^\s*#define\s+AppVersionInfo\s+"([^"]*)"',
        multiLine: true,
      ).allMatches(iss).map((m) => m.group(1)).toList();

      expect(defines, ['0.0.0.0']);
      expect(iss, contains('#ifndef AppVersionInfo'));
    });

    test('[Setup] stamps both the displayed and the file-property version', () {
      expect(
        iss,
        contains(RegExp(r'^AppVersion=\{#AppVersion\}$', multiLine: true)),
        reason: 'DisplayVersion in Apps & Features comes from this.',
      );
      expect(
        iss,
        contains(
          RegExp(r'^VersionInfoVersion=\{#AppVersionInfo\}$', multiLine: true),
        ),
        reason: "So the setup .exe's own file properties carry the version.",
      );
    });
  });

  group('build_release.ps1 hands the bumped version to ISCC', () {
    test('the numeric VersionInfo form is derived from the bump', () {
      expect(
        script,
        contains(RegExp(r'\$versionInfo\s*=\s*"\$ver\.\$build"')),
        reason:
            'VersionInfoVersion must be numeric a.b.c.d — the "+" of '
            'x.y.z+build is an Inno Setup compile error — so the build '
            'number becomes the fourth field.',
      );
    });

    test('the ISCC invocation passes both defines', () {
      final iscc = RegExp(
        r'^\s*&\s*\$iscc\s+(.*)$',
        multiLine: true,
      ).firstMatch(script);

      expect(
        iscc,
        isNotNull,
        reason: r'ISCC is no longer invoked as `& $iscc ...`.',
      );
      final args = iscc!.group(1)!;
      expect(
        args,
        contains(r'/DAppVersion=$fullVersion'),
        reason: 'Without this the .iss falls back to 0.0.0.',
      );
      expect(args, contains(r'/DAppVersionInfo=$versionInfo'));
    });

    test('pubspec.yaml stays the single source of the version', () {
      // The script derives $ver/$build from this exact shape; if pubspec ever
      // stops matching it, step 1 throws and the defines above are meaningless.
      expect(
        pubspec,
        contains(RegExp(r'^version:\s*\d+\.\d+\.\d+\+\d+$', multiLine: true)),
      );
    });
  });
}
