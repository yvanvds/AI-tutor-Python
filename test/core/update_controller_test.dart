// #47: the update flow used to live inline in `AppShell.initState`, where
// nothing could reach it without a real network and a real installer — the
// only thing any test did with it was switch it off. These drive the whole
// orchestration through the seams: no socket, no temp file, no process.

import 'dart:async';
import 'dart:io';

import 'package:ai_tutor_python/core/github_release.dart';
import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateInfo _release(String version) => UpdateInfo(
  version,
  Uri.parse('https://example.com/python_teacher_install.exe'),
  'abc123',
);

/// Records what the controller asked of the outside world, so a test can
/// assert on what was *not* done — no download without consent, no installer
/// after a hash mismatch.
class _Seams {
  _Seams({
    this.localVersion = '2.0.0+17',
    this.autoCheck = true,
    this.latest,
    this.feedError,
    this.verifies = true,
    this.downloadError,
    this.progress = const [],
  });

  final String localVersion;
  final bool autoCheck;
  final UpdateInfo? latest;
  final Object? feedError;
  final bool verifies;
  final Object? downloadError;

  /// Fractions the fake downloader reports before it returns.
  final List<double> progress;

  int feedCalls = 0;
  int downloadCalls = 0;
  int verifyCalls = 0;
  final List<File> ran = <File>[];
  final List<String> logs = <String>[];

  final File installer = File('does-not-need-to-exist.exe');

  UpdateServices get services => UpdateServices(
    localVersion: localVersion,
    autoCheck: autoCheck,
    feed: () async {
      feedCalls++;
      if (feedError != null) throw feedError!;
      return latest;
    },
    download: (release, onProgress) async {
      downloadCalls++;
      if (downloadError != null) throw downloadError!;
      for (final fraction in progress) {
        onProgress(fraction);
      }
      return installer;
    },
    verify: (file, expected) async {
      verifyCalls++;
      return verifies;
    },
    run: (file) async => ran.add(file),
    log: logs.add,
  );
}

ProviderContainer _containerFor(_Seams seams) {
  final container = ProviderContainer(
    overrides: [updateServicesProvider.overrideWithValue(seams.services)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('check', () {
    test('offers a newer release', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).check();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.release?.version, '2.1.0+20');
      expect(state.isOffering, isTrue);
      expect(state.message, contains('2.1.0+20'));
    });

    test('offers nothing for an older or equal release', () async {
      for (final version in ['2.0.0+17', '2.0.0+16', '1.9.9']) {
        final seams = _Seams(latest: _release(version));
        final container = _containerFor(seams);

        await container.read(updateControllerProvider.notifier).check();

        final state = container.read(updateControllerProvider);
        expect(state.phase, UpdatePhase.upToDate, reason: version);
        expect(state.release, isNull, reason: version);
        expect(state.isOffering, isFalse, reason: version);
      }
    });

    test(
      'reports "nothing published" as up to date, not as a failure',
      () async {
        final seams = _Seams(latest: null);
        final container = _containerFor(seams);

        await container.read(updateControllerProvider.notifier).check();

        final state = container.read(updateControllerProvider);
        expect(state.phase, UpdatePhase.upToDate);
        expect(state.release, isNull);
      },
    );

    // An unreadable local version must never read as "everything published is
    // newer" — that would install a release over a build nobody can identify.
    test('declines to compare against an unreadable local version', () async {
      final seams = _Seams(
        localVersion: 'unknown',
        latest: _release('2.1.0+20'),
      );
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).check();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.release, isNull);
      expect(state.isOffering, isFalse);
      expect(state.message, contains('unknown'));
      expect(seams.downloadCalls, 0);
    });

    // #46 gave the failure a type; #47 gives it somewhere to be seen; #48
    // renders `message` beside About's check button.
    test('parks a failed check on the state instead of throwing', () async {
      final seams = _Seams(
        feedError: UpdateCheckException('release lookup returned HTTP 500'),
      );
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).check();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.release, isNull);
      expect(state.message, contains('HTTP 500'));
      expect(seams.logs, isNotEmpty);
    });

    test('a second check while one is in flight is ignored', () async {
      final gate = Completer<void>();
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = ProviderContainer(
        overrides: [
          updateServicesProvider.overrideWithValue(
            UpdateServices(
              localVersion: '2.0.0+17',
              feed: () async {
                seams.feedCalls++;
                await gate.future;
                return _release('2.1.0+20');
              },
              download: (_, _) async => throw StateError('not reached'),
              verify: (_, _) async => true,
              run: (_) async => throw StateError('not reached'),
              log: seams.logs.add,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(updateControllerProvider.notifier);
      final first = controller.check();
      await controller.check();
      expect(seams.feedCalls, 1);

      gate.complete();
      await first;
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.available,
      );
    });
  });

  group('autoCheck', () {
    // The dev-build gate: a debug checkout is developed against, not updated.
    test('start() does not check when autoCheck is off', () async {
      final seams = _Seams(autoCheck: false, latest: _release('2.1.0+20'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).start();

      expect(seams.feedCalls, 0);
      expect(container.read(updateControllerProvider).phase, UpdatePhase.idle);
    });

    // ...but the manual check in #48 still has to work on such a build.
    test('an explicit check() still runs when autoCheck is off', () async {
      final seams = _Seams(autoCheck: false, latest: _release('2.1.0+20'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).check();

      expect(seams.feedCalls, 1);
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.available,
      );
    });

    test('start() checks when autoCheck is on', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).start();

      expect(seams.feedCalls, 1);
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.available,
      );
    });
  });

  group('apply', () {
    test('installs an offered, verified release', () async {
      final seams = _Seams(
        latest: _release('2.1.0+20'),
        progress: const [0.5, 1],
      );
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      await controller.apply();

      expect(seams.downloadCalls, 1);
      expect(seams.verifyCalls, 1);
      expect(seams.ran, [seams.installer]);
      // `run` only returns when the handover failed, so the state after a
      // fake that returns is `failed` with the installer's path — the real
      // one never comes back.
      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.message, contains(seams.installer.path));
    });

    // The whole reason the seams exist: nothing but a user action reaches an
    // installer. No branch of the check calls apply, and no timer can.
    test('a check on its own never downloads or installs', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).start();

      expect(seams.downloadCalls, 0);
      expect(seams.verifyCalls, 0);
      expect(seams.ran, isEmpty);
    });

    test('apply() with nothing on offer does nothing', () async {
      final seams = _Seams(latest: null);
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.apply();
      await controller.check();
      await controller.apply();

      expect(seams.downloadCalls, 0);
      expect(seams.ran, isEmpty);
    });

    test('never starts an installer that failed its checksum', () async {
      final seams = _Seams(latest: _release('2.1.0+20'), verifies: false);
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      await controller.apply();

      expect(seams.verifyCalls, 1);
      expect(seams.ran, isEmpty, reason: 'an unverified binary was launched');
      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.message, contains('checksum'));
    });

    test('reports a failed download instead of throwing', () async {
      final seams = _Seams(
        latest: _release('2.1.0+20'),
        downloadError: UpdateCheckException('installer download stalled'),
      );
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      await controller.apply();

      expect(seams.ran, isEmpty);
      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.message, contains('stalled'));
    });

    test('reports download progress on the state', () async {
      // Read back through the provider rather than through a listener: this
      // is exactly what the progress bar renders (#48).
      late final ProviderContainer container;
      final seen = <double>[];
      final installer = File('does-not-need-to-exist.exe');
      container = ProviderContainer(
        overrides: [
          updateServicesProvider.overrideWithValue(
            UpdateServices(
              localVersion: '2.0.0+17',
              feed: () async => _release('2.1.0+20'),
              download: (_, onProgress) async {
                for (final fraction in const [0.25, 0.75, 2.0]) {
                  onProgress(fraction);
                  seen.add(container.read(updateControllerProvider).progress);
                }
                return installer;
              },
              verify: (_, _) async => true,
              run: (_) async {},
              log: (_) {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      await controller.apply();

      // The last one is clamped: a server that lies about its content length
      // must not push a progress bar past full.
      expect(seen, [0.25, 0.75, 1.0]);
    });
  });

  // #48: the offer waits instead of interrupting, so it needs somewhere to
  // wait and a way to be put away. Before this the "offer" was a modal with
  // one OK button that started the install when it closed.
  group('dismiss', () {
    test('Later hides the bar but keeps the release for About', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      expect(container.read(updateControllerProvider).isOffering, isTrue);

      controller.dismiss();

      final state = container.read(updateControllerProvider);
      expect(state.dismissed, isTrue);
      expect(state.isOffering, isFalse);
      expect(state.release?.version, '2.1.0+20');
      expect(state.phase, UpdatePhase.available);
      expect(seams.downloadCalls, 0, reason: 'Later downloaded something');
    });

    test('a later check offers again', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      controller.dismiss();
      await controller.check();

      expect(container.read(updateControllerProvider).isOffering, isTrue);
    });

    test('an offer that was dismissed can still be applied', () async {
      final seams = _Seams(latest: _release('2.1.0+20'));
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      controller.dismiss();
      await controller.apply();

      expect(seams.downloadCalls, 1);
      expect(seams.ran, [seams.installer]);
    });

    // A bar that vanished mid-download would leave a ~250 MB install running
    // with nothing on screen saying so.
    test('a dismissal during the download is refused', () async {
      final gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          updateServicesProvider.overrideWithValue(
            UpdateServices(
              localVersion: '2.0.0+17',
              feed: () async => _release('2.1.0+20'),
              download: (_, _) async {
                await gate.future;
                return File('does-not-need-to-exist.exe');
              },
              verify: (_, _) async => true,
              run: (_) async {},
              log: (_) {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      final applying = controller.apply();
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.downloading,
      );

      controller.dismiss();
      expect(container.read(updateControllerProvider).isOffering, isTrue);

      gate.complete();
      await applying;
    });

    // The bar is where progress and the outcome are shown, so it has to
    // outlast the accept — including into a failed apply, which is the one
    // failure a student needs to see without going looking for it.
    test('the bar stays through the download and a failed apply', () async {
      final seams = _Seams(latest: _release('2.1.0+20'), verifies: false);
      final container = _containerFor(seams);
      final controller = container.read(updateControllerProvider.notifier);

      await controller.check();
      await controller.apply();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.isOffering, isTrue);
    });

    // A *check* that failed has no release, so nothing is pushed at anybody;
    // the reason waits in About.
    test('a failed check shows no bar', () async {
      final seams = _Seams(feedError: UpdateCheckException('offline'));
      final container = _containerFor(seams);

      await container.read(updateControllerProvider.notifier).check();

      expect(container.read(updateControllerProvider).isOffering, isFalse);
    });
  });

  group('production wiring', () {
    test('a null feed URL means no feed and no auto check', () async {
      final container = ProviderContainer(
        overrides: [
          updateFeedUrlProvider.overrideWithValue(null),
          updateAutoCheckProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      final services = container.read(updateServicesProvider);
      expect(services.autoCheck, isFalse);
      expect(await services.feed(), isNull);
    });

    test('the feed URL alone does not turn the check on', () {
      final container = ProviderContainer(
        overrides: [
          updateFeedUrlProvider.overrideWithValue(
            Uri.parse('https://example.com/releases/latest'),
          ),
          updateAutoCheckProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(updateServicesProvider).autoCheck, isFalse);
    });

    // #50: the shipped default is the Releases API, not a manifest on a
    // static host that has to be kept in lockstep with the release.
    test('the shipped feed is this repository\'s latest release', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(updateFeedUrlProvider), kLatestReleaseEndpoint);
    });
  });
}
