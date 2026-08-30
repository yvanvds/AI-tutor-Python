// End-to-end harness (#28): boots the real app — `GoalsApp` from
// `main.dart`, the real shell, pages, services and polling streams — on a
// desktop device with the two external systems swapped for fakes:
//
//   - Cosmos: `InMemoryCosmosClient` is installed as the process-wide
//     `CosmosClient.instance`, so every `CosmosPaths.*()` handle resolves to
//     an in-memory container seeded from `seed.dart`.
//   - Entra: `authServiceProvider` is overridden with a notifier that is
//     born signed in. The bypass lives only in this file, which is compiled
//     into the integration-test entrypoints and never into
//     `flutter build windows` — there is no flag in `lib/` to flip.
//
// Also pinned so a run is deterministic and leaves no trace on the machine:
// the system locale, SharedPreferences (in-memory), the playground file
// directory (temp), the update check (off), the LLM (any call fails loudly)
// and the lesson example runner (scripted). Python for the practice editor
// stays real by default — pressing Run on a machine without the bundle shows
// the in-app host error, which is what a student would see; a flow that needs
// to drive a run deterministically passes `pyRunner:`.

import 'dart:async';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/progress/progress_archive_io.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:py_runner/py_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/helpers/fake_lesson_code_runner.dart';
import '../../test/helpers/in_memory_cosmos.dart';
import 'seed.dart';

/// Signed in from the first frame; `tryAcquireTokenSilent` / `signIn` are
/// never reached. `signOut` still works so a sign-out flow can be driven.
class _SignedInAuth extends AuthService {
  _SignedInAuth(this._identity);
  final AccountIdentity _identity;

  @override
  AccountIdentity? build() => _identity;

  @override
  Future<void> tryAcquireTokenSilent() async {}

  @override
  Future<void> signIn() async => state = _identity;

  @override
  Future<void> signOut() async => state = null;
}

/// Unstubbed mock: any attempt to talk to OpenAI throws `MissingStubError`,
/// so a flow that unexpectedly needs the LLM fails instead of hanging.
class _NoLlm extends Mock implements OpenaiConnector {}

/// The real tutor (session init, target selection, curriculum watch) minus
/// the one automatic LLM entry point: mounting the practice editor asks for
/// an exercise, which needs a model.
class _OfflineTutor extends TutorService {
  _OfflineTutor() : super(connectorOverride: _NoLlm());

  @override
  Future<void> requestExercise() async {}
}

/// Replaces only the *dialog* half of progress export / import (#32): the
/// path is fixed instead of asked for, and the file is still written to and
/// read from the real disk, so a flow exercises the same round trip a student
/// does.
class _FixedPathArchiveIo implements ProgressArchiveIo {
  _FixedPathArchiveIo(this.file);
  final File file;

  @override
  Future<String?> save({
    required String suggestedName,
    required String contents,
  }) async {
    await file.writeAsString(contents);
    return file.path;
  }

  @override
  Future<ArchiveFile?> open() async {
    if (!file.existsSync()) return null;
    return (name: 'progress.json', contents: await file.readAsString());
  }
}

class AppHarness {
  AppHarness({
    this.identity = studentIdentity,
    this.updateFeedUrl,
    this.forceUpdateCheck = true,
    this.pyRunner,
    this.archiveFile,
    Map<String, LessonRunResult> lessonResults = const {},
  }) : lessonRunner = FakeLessonCodeRunner(results: lessonResults);

  final AccountIdentity identity;

  /// Where the shell looks for a published release on launch — GitHub's
  /// `/releases/latest` in production (#50). `null` (the default) switches
  /// the update check off, so a flow never fetches, downloads or runs an
  /// installer. The update flows point this at a local test server that
  /// answers with the same API shape.
  final Uri? updateFeedUrl;

  /// Whether the harness forces the launch check on.
  ///
  /// The app itself checks only in a release build (#47), and an
  /// integration-test binary is never one, so a flow that wants to drive the
  /// check has to say so. Pass `false` to leave the app's own
  /// `kReleaseMode` default in place — which is how `update_dev_build.dart`
  /// proves a debug build never reaches out at all.
  final bool forceUpdateCheck;

  /// Scripted stand-in for the bundled Python behind lesson examples.
  /// `lessonRunner.ran` lists every `<pre class="run">` the page asked for.
  final FakeLessonCodeRunner lessonRunner;

  /// Python host behind the editor's Run button. `null` (the default) leaves
  /// the real one in place — pressing Run on a machine without the bundle
  /// then shows the in-app host error, which is what a student would see.
  /// Pass a [FakePyRunner] to drive a run that starts and keeps running
  /// regardless of what is installed on the machine.
  final PyRunner? pyRunner;

  /// Where "Export progress…" writes and "Import progress…" reads (#32).
  /// `null` (the default) leaves the real OS file dialogs in place, which no
  /// test can click; pass a path in a temp directory to drive the round trip.
  final File? archiveFile;

  /// Every installer handover the app performed, as `(executable, arguments)`
  /// (#49).
  ///
  /// The launcher is *always* replaced, in every flow: the production one
  /// spawns a real setup binary on the machine running the suite and then
  /// calls `exit(0)`, which would take the test runner with it. Everything
  /// above it — the feed, the download, the checksum — stays the real wiring,
  /// so a flow can assert on the switches the app passes the installer.
  final List<({String executable, List<String> arguments})> installerLaunches =
      <({String executable, List<String> arguments})>[];

  late final InMemoryCosmosClient cosmos;
  late final Directory playgroundDir;
  ProviderContainer? _container;

  /// The app's provider container; read services / state the way the
  /// widgets do (e.g. `harness.container.read(codeServiceProvider(mode))`).
  ProviderContainer get container => _container!;

  Future<void> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    cosmos = InMemoryCosmosClient(seedCosmos(identity))..install();
    playgroundDir = Directory.systemTemp.createTempSync('ai_tutor_it_');

    _container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith(() => _SignedInAuth(identity)),
        tutorServiceProvider.overrideWith(_OfflineTutor.new),
        lessonCodeRunnerProvider.overrideWithValue(lessonRunner),
        playgroundFileStoreProvider.overrideWithValue(
          PlaygroundFileStore(rootDir: () async => playgroundDir),
        ),
        if (pyRunner != null) pyRunnerProvider.overrideWithValue(pyRunner!),
        if (archiveFile != null)
          progressArchiveIoProvider.overrideWithValue(
            _FixedPathArchiveIo(archiveFile!),
          ),
        updateFeedUrlProvider.overrideWithValue(updateFeedUrl),
        installerLauncherProvider.overrideWithValue((executable, arguments) {
          installerLaunches.add((executable: executable, arguments: arguments));
          // The real launcher never returns — it exits the process. Hanging
          // here keeps the app in `applying`, which is the state a student
          // actually sees for the moment before the window closes.
          return Completer<void>().future;
        }),
        if (forceUpdateCheck)
          updateAutoCheckProvider.overrideWithValue(updateFeedUrl != null),
        systemLocaleProvider.overrideWithValue(const Locale('en', 'US')),
      ],
    );

    // Same root and scope as `main()`.
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GoalsApp()),
    );
    await pumpUntil(tester, () => find.byType(AppShell).evaluate().isNotEmpty);
  }

  /// Unmounts the app and tears down services, timers and temp files.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    _container?.dispose();
    _container = null;
    if (playgroundDir.existsSync()) {
      playgroundDir.deleteSync(recursive: true);
    }
  }
}

/// Pumps real frames until [condition] holds. Preferred over
/// `pumpAndSettle` here: the code editor's cursor blink and the 5 s Cosmos
/// polls mean the app never fully settles.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'pumpUntil timed out after $timeout${reason == null ? '' : ': $reason'}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

/// Pumps until [finder] matches at least one widget.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  reason: 'nothing matched $finder',
);

/// Pumps until [finder] matches nothing — e.g. a dialog route that is still
/// animating out after its result has already been acted on.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) => pumpUntil(
  tester,
  () => finder.evaluate().isEmpty,
  timeout: timeout,
  reason: 'still matched $finder',
);
