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
// stays real — pressing Run on a machine without the bundle shows the
// in-app host error, which is what a student would see.

import 'dart:io';

import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

class AppHarness {
  AppHarness({
    this.identity = studentIdentity,
    Map<String, LessonRunResult> lessonResults = const {},
  }) : lessonRunner = FakeLessonCodeRunner(results: lessonResults);

  final AccountIdentity identity;

  /// Scripted stand-in for the bundled Python behind lesson examples.
  /// `lessonRunner.ran` lists every `<pre class="run">` the page asked for.
  final FakeLessonCodeRunner lessonRunner;

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
        updateManifestUrlProvider.overrideWithValue(null),
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
