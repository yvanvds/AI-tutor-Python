// #49: the app's half of "an update needs no administrator and the app comes
// back". The installer's half — per-user install under %LOCALAPPDATA%, and the
// `[Run]` entry guarded by `WantsRelaunch` — lives in
// `windows/packaging/exe/installer.iss` and cannot be reached from Dart. What
// can be, and what these pin, is the command line the app hands it: drop
// `/RELAUNCH=1` and the installer's only unguarded `[Run]` entry is
// `skipifsilent`, so the app updates and never returns.

import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the silent install arguments carry the relaunch switch', () {
    expect(
      kSilentInstallArguments,
      containsAll(<String>[
        '/SILENT',
        '/NOCANCEL',
        '/NORESTART',
        '/RELAUNCH=1',
      ]),
    );
    // `/VERYSILENT` shows the student nothing at all while ~250 MB is
    // unpacked, which reads as a crash.
    expect(kSilentInstallArguments, isNot(contains('/VERYSILENT')));
  });

  test(
    'the production run seam launches the downloaded file with them',
    () async {
      final calls = <({String executable, List<String> arguments})>[];
      final container = ProviderContainer(
        overrides: [
          // No feed: this test is about the handover, and an unoverridden feed
          // URL would point the services at the real GitHub API.
          updateFeedUrlProvider.overrideWithValue(null),
          installerLauncherProvider.overrideWithValue((
            executable,
            arguments,
          ) async {
            calls.add((executable: executable, arguments: arguments));
          }),
        ],
      );
      addTearDown(container.dispose);

      final installer = File('C:\\Temp\\python_teacher_install.exe');
      await container.read(updateServicesProvider).run(installer);

      expect(calls, hasLength(1));
      expect(calls.single.executable, installer.path);
      expect(calls.single.arguments, kSilentInstallArguments);
    },
  );
}
