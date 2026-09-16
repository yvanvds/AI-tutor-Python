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
// the window size (see [AppHarness.windowSize]), the system locale, the
// system light/dark setting, SharedPreferences (in-memory), the playground
// file directory (temp), the update check (off),
// its native fallback transport (none — see [AppHarness.nativeGet]) and the
// proxy it would go through (none — see [AppHarness.proxy]), the LLM (any
// call fails loudly unless a flow passes `llm:` or `openaiClient:`), the
// school's OpenAI key (a fixed string — see
// [kSchoolApiKey]), the lesson example runner (scripted), the browser
// launcher (recorded, never opened — see [browserLaunches]) and the sound
// effects (silent — see [_NoSound]).
//
// The light/dark pin is not cosmetic (#32): with no stored preference the app
// follows the operating system, so an unpinned run renders in whatever theme
// the machine happens to be set to — green on a developer's dark desktop, red
// on a CI runner that ships in light mode. Every flow therefore states the
// brightness it wants, and the default matches the app's shipping look.
//
// Python for the practice editor stays real by default — pressing Run on a
// machine without the bundle shows the in-app host error, which is what a
// student would see; a flow that needs to drive a run deterministically
// passes `pyRunner:`.

import 'dart:async';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/services/github/github_device_flow.dart';
import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/progress/progress_archive_io.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/openai_wiring.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:py_runner/py_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/helpers/fake_lesson_code_runner.dart';
import '../../test/helpers/in_memory_cosmos.dart';
import 'fake_github_server.dart';
import 'fake_release_server.dart';
import 'scripted_llm.dart';
import 'seed.dart';

/// The school's OpenAI key as every flow sees it (#126). Pinned in place of
/// the build's real `Env.apiKey` so a flow can assert on the key a request
/// carried without the developer's own key ever appearing in a test.
const String kSchoolApiKey = 'sk-school-key';

/// The window the Windows runner creates the app in, in logical pixels
/// (`windows/runner/main.cpp`), and the size every flow lays out at unless
/// it says otherwise — see [AppHarness.windowSize].
const Size kRunnerWindowSize = Size(1280, 720);

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

/// Silent stand-in for the tutor's sound effects (#100). The real one plays
/// through the speakers of whatever machine runs the suite, and audioplayers
/// keeps a frame callback ticking past the end of the clip — a flow that
/// ends while the "correct answer" note is still sounding fails with "an
/// animation is still running even after the widget tree was disposed".
class _NoSound extends SoundService {
  @override
  Future<void> correctAnswer() async {}
  @override
  Future<void> askQuestion() async {}
  @override
  Future<void> playGoalReached() async {}
  @override
  Future<void> guidingComplete() async {}
}

/// What the app asked the save dialog for (#127): the name it suggested and
/// the extension filter it set — the two things the fixed path below takes
/// out of a flow's sight.
typedef FileSaveRequest = ({String suggestedName, List<String> extensions});

/// Replaces only the *dialog* half of progress export / import (#32) and of
/// the bug report's `Save as file` (#127): the path is fixed instead of
/// asked for, and the file is still written to and read from the real disk,
/// so a flow exercises the same round trip a student does.
class _FixedPathArchiveIo implements ProgressArchiveIo {
  _FixedPathArchiveIo(this.file, {required this.onSave});
  final File file;
  final void Function(FileSaveRequest request) onSave;

  @override
  Future<String?> save({
    required String suggestedName,
    required String contents,
    List<String> allowedExtensions = const ['json'],
  }) async {
    onSave((suggestedName: suggestedName, extensions: allowedExtensions));
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
    this.nativeGet,
    this.proxy,
    this.pacUrl,
    this.appVersion,
    this.prefs = const {},
    this.windowSize = kRunnerWindowSize,
    this.pyRunner,
    this.archiveFile,
    this.systemBrightness = Brightness.dark,
    this.github,
    this.githubOAuthClientId,
    this.llm,
    this.openaiClient,
    this.developerTools,
    this.supervision,
    this.extraDocs = const {},
    Map<String, LessonRunResult> lessonResults = const {},
  }) : assert(
         llm == null || openaiClient == null,
         'llm: replaces the connectors, openaiClient: keeps them; pick one',
       ),
       assert(
         proxy == null || pacUrl == null,
         'proxy: hands the app the resolved setting, pacUrl: makes it resolve '
         'one; pick one',
       ),
       lessonRunner = FakeLessonCodeRunner(results: lessonResults);

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

  /// The transport the updater falls back to when Dart cannot complete a
  /// TLS handshake (#124). `null` (the default) means none — a test boot
  /// never spawns the `curl.exe` the production wiring would, and a flow
  /// that serves its release over a certificate Dart refuses sees the app
  /// fail the way it fails on a machine with no fallback. The TLS flow
  /// passes [TrustingLoopbackGet], which trusts that one certificate the way
  /// Schannel trusts a school filter's CA.
  final NativeGet? nativeGet;

  /// The proxy the updater's requests go through (#133). `null` (the
  /// default) pins it to none, so a test boot never depends on the machine
  /// it runs on having a proxy set — the production wiring would read the
  /// environment, Internet Options and its PAC script. The proxy flow passes
  /// a loopback `LoopbackProxy`, the one route to its release server.
  final UpdateProxy? proxy;

  /// A proxy auto-configuration script for the app to resolve (#135), the
  /// way Internet Options would name one under "Use automatic configuration
  /// script". Unlike [proxy], this hands the app nothing resolved: the
  /// production `systemUpdateProxy` runs, with the environment and the
  /// explicit Internet Options pinned to none and the auto-configuration
  /// pinned to this URL, and the real WinHTTP fetches and evaluates the
  /// script. The PAC flow serves one from a loopback server that names its
  /// `LoopbackProxy`.
  final Uri? pacUrl;

  /// The version this build reports (#119). `null` (the default) leaves the
  /// real `kAppVersion` from `version.dart` in place, which is what every
  /// flow that is not about versions wants. A flow that has to look like the
  /// build an installer just put down — the "What's new" overlay only fires
  /// when the stashed notes name the *running* version — pins it here rather
  /// than editing a generated file.
  final String? appVersion;

  /// SharedPreferences the app starts with (#119).
  ///
  /// The store is always pinned in-memory and always starts empty, so a run
  /// leaves nothing on the machine and no flow inherits another's choices.
  /// This seeds it instead, for a flow whose subject is what a *previous*
  /// launch left behind.
  final Map<String, Object> prefs;

  /// The size, in logical pixels, the app lays out at (#138).
  ///
  /// Defaults to [kRunnerWindowSize], the window the Windows runner creates.
  /// Pinned through the test view rather than left to the real window: on a
  /// display too small for that window the app would get less, and the
  /// theory view starts with the chat folded under 1200 px — every flow that
  /// types into the chat from the theory page would then meet a strip. A
  /// flow about the window width passes its own size, and can resize
  /// mid-flow through `tester.view.physicalSize` the way this does.
  final Size windowSize;

  /// Scripted stand-in for the bundled Python behind lesson examples.
  /// `lessonRunner.ran` lists every `<pre class="run">` the page asked for.
  final FakeLessonCodeRunner lessonRunner;

  /// Python host behind the editor's Run button. `null` (the default) leaves
  /// the real one in place — pressing Run on a machine without the bundle
  /// then shows the in-app host error, which is what a student would see.
  /// Pass a [FakePyRunner] to drive a run that starts and keeps running
  /// regardless of what is installed on the machine.
  final PyRunner? pyRunner;

  /// The operating system's light/dark setting, as the app sees it (#32).
  ///
  /// Defaults to dark — the theme the app shipped with, and the one the rest
  /// of the flows describe. Pass `Brightness.light` to drive the other
  /// resolution of "follow the system". Never left to the real machine: that
  /// is what made the theme flow pass on a dark desktop and fail on CI.
  final Brightness systemBrightness;

  /// Where "Export progress…" writes and "Import progress…" reads (#32), and
  /// where the bug report's "Save as file" lands (#127). `null` (the
  /// default) leaves the real OS file dialogs in place, which no test can
  /// click; pass a path in a temp directory to drive the round trip.
  final File? archiveFile;

  /// Every save dialog the app would have opened over [archiveFile], in
  /// order: the file name it suggested and the extension filter it asked
  /// for (#127). The fixed path hides both from the file on disk.
  final List<FileSaveRequest> fileSaves = <FileSaveRequest>[];

  /// GitHub, as the bug reporter talks to it (#57). `null` (the default)
  /// leaves the production hosts in place, which costs nothing: no flow
  /// starts a sign-in by itself, and a build with no OAuth client id has no
  /// sign-in to start.
  final FakeGitHubServer? github;

  /// The OAuth client id the app believes it was compiled with.
  ///
  /// `null` leaves the real one from `.env` — which on a developer checkout
  /// and on CI is empty, i.e. "no OAuth app registered". A flow that drives
  /// the sign-in passes one; a flow that drives the *unconfigured* card
  /// passes `''` explicitly rather than relying on the machine's `.env`.
  final String? githubOAuthClientId;

  /// The model behind the tutor (#78).
  ///
  /// `null` (the default) leaves the LLM off entirely: any call throws and
  /// mounting the practice editor never asks for an exercise, which is what
  /// every flow that is not about the tutor wants. Pass a [ScriptedLlm] to
  /// run the *real* `TutorService` — session init, conductor, request
  /// building, streaming, response dispatch and retry — against canned
  /// assistant text.
  final ScriptedLlm? llm;

  /// OpenAI as an HTTP endpoint, for a flow about what the app puts *on the
  /// wire* (#126).
  ///
  /// Where [llm] swaps the connectors for a scripted stand-in, this leaves
  /// the production wiring in place — the tutor's connector, the grade
  /// justification's and the Test button's, each built the way `lib/`
  /// builds it, resolving its key through `tutorApiKeyProvider` — and only
  /// replaces the socket underneath, through `openaiClientProvider`. Pass a
  /// `FakeOpenAi().client` (test/helpers) to read back every request the
  /// real app made, header and body, and to answer it. Mounting the practice
  /// editor then really asks the model for an exercise, so the client has to
  /// be ready to answer one.
  final http.Client? openaiClient;

  /// Whether developer-only surfaces (the instructions editor, the developer
  /// card and — on its own — the AI model card in Options) are exposed.
  ///
  /// `null` (the default) leaves the app's own rule in place, which is
  /// `kDebugMode` — and an integration-test binary is a debug build, so by
  /// default every flow runs *with* developer tools. A flow about who gets
  /// to see something that developer builds see anyway (#90) passes `false`,
  /// so it proves the role gate rather than the debug gate.
  final bool? developerTools;

  /// The classroom-supervision registry the tutor consults when it grades an
  /// answer (#100). `null` (the default) leaves the app's own binding in
  /// place — no registry, every turn is home work — which is also what the
  /// shipped app does until Anchor is wired up. A flow about the supervised
  /// weight passes a stand-in that says "in session".
  final SupervisionSource? supervision;

  /// Cosmos docs upserted on top of the standard seed before the app boots,
  /// keyed by container name as `CosmosPaths` names them (#101). A doc whose
  /// id already exists in the seed replaces it, so a flow can start a
  /// student mid-curriculum — beliefs, progress, an edited goal — instead
  /// of on the first exercise.
  final Map<String, List<Map<String, dynamic>>> extraDocs;

  /// Every URL the app asked the operating system to open (#57).
  ///
  /// The launcher is always replaced, in every flow: the production one hands
  /// a URL to Windows, which during a test run means a browser window opening
  /// on the machine running the suite.
  final List<Uri> browserLaunches = <Uri>[];

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

  /// Boots the app and, by default, waits for the shell — the screen every
  /// flow on a seeded account lands on. A flow about the screens *before*
  /// the shell (the local-key gate, #126) passes `waitForShell: false` and
  /// waits for what it expects itself.
  Future<void> boot(WidgetTester tester, {bool waitForShell = true}) async {
    // Logical size times the machine's ratio: the layout is the same on a
    // 100 % desktop and a 150 % laptop. Reset in a tear-down, not in
    // [dispose], so a failed flow cannot hand its size to the next one in
    // the same process (app_test.dart).
    tester.view.physicalSize = windowSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues(Map<String, Object>.of(prefs));
    cosmos = InMemoryCosmosClient(seedCosmos(identity))..install();
    for (final entry in extraDocs.entries) {
      for (final doc in entry.value) {
        cosmos[entry.key].upsert(doc);
      }
    }
    playgroundDir = Directory.systemTemp.createTempSync('ai_tutor_it_');

    final openaiClient = this.openaiClient;
    _container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith(() => _SignedInAuth(identity)),
        // Never the build's real key (#126): the school-key account's calls
        // are asserted against this string, and a developer's own key must
        // not leak into a test.
        schoolApiKeyProvider.overrideWithValue(kSchoolApiKey),
        if (openaiClient != null)
          // The production connectors, over a scripted socket.
          openaiClientProvider.overrideWithValue(openaiClient)
        else ...[
          tutorServiceProvider.overrideWith(
            llm == null
                ? _OfflineTutor.new
                : () => TutorService(connectorOverride: llm!),
          ),
          // The grade justification (#99) has its own connector; the same
          // scripted model stands in for it, and with no script it fails
          // loudly like every other LLM call.
          gradeJustificationConnectorProvider.overrideWithValue(
            llm ?? _NoLlm(),
          ),
          // So does the Test button behind the model fields in Options
          // (#125): `ScriptedLlm.probeResults` says what each id answers.
          modelProbeConnectorProvider.overrideWithValue(llm ?? _NoLlm()),
        ],
        lessonCodeRunnerProvider.overrideWithValue(lessonRunner),
        playgroundFileStoreProvider.overrideWithValue(
          PlaygroundFileStore(rootDir: () async => playgroundDir),
        ),
        if (pyRunner != null) pyRunnerProvider.overrideWithValue(pyRunner!),
        if (archiveFile != null)
          progressArchiveIoProvider.overrideWithValue(
            _FixedPathArchiveIo(archiveFile!, onSave: fileSaves.add),
          ),
        if (github != null) ...[
          gitHubOAuthBaseProvider.overrideWithValue(github!.base),
          gitHubApiBaseProvider.overrideWithValue(github!.base),
        ],
        if (githubOAuthClientId != null)
          gitHubOAuthClientIdProvider.overrideWithValue(githubOAuthClientId!),
        if (developerTools != null)
          developerToolsProvider.overrideWithValue(developerTools!),
        if (supervision != null)
          supervisionSourceProvider.overrideWithValue(supervision!),
        soundServiceProvider.overrideWithValue(_NoSound()),
        browserLauncherProvider.overrideWithValue((Uri url) async {
          browserLaunches.add(url);
          return true;
        }),
        if (appVersion != null)
          appVersionProvider.overrideWithValue(appVersion!),
        updateFeedUrlProvider.overrideWithValue(updateFeedUrl),
        nativeGetProvider.overrideWithValue(nativeGet),
        if (pacUrl == null)
          updateProxyProvider.overrideWithValue(fixedUpdateProxy(proxy))
        else
          updateProxyProvider.overrideWithValue(
            updateProxyResolvedOnce(
              () => systemUpdateProxy(
                updateFeedUrl!,
                environment: const <String, String>{},
                internetSettings: () =>
                    (enabled: false, server: null, override: null),
                autoProxyConfig: () =>
                    (autoDetect: false, configUrl: pacUrl.toString()),
                windows: true,
              ),
            ),
          ),
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
        systemBrightnessProvider.overrideWithValue(systemBrightness),
      ],
    );

    // Same root and scope as `main()`.
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GoalsApp()),
    );
    if (waitForShell) {
      await pumpUntil(
        tester,
        () => find.byType(AppShell).evaluate().isNotEmpty,
      );
    }
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
///
/// The reason names the finder itself (`describeSelf`), not its last result:
/// a plain `$finder` prints what the finder *found last time*, and a finder
/// shared across the tests of one flow still holds the previous test's
/// elements — unmounted with that test's app, and a null-check crash to
/// describe (#133).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  reason: 'nothing matched ${finder.toString(describeSelf: true)}',
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
  reason: 'still matched ${finder.toString(describeSelf: true)}',
);
