import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/app_start.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/core/local_cosmos_client.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/core/update_required.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/features/school/first_start_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/standalone/standalone_welcome_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/update_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/auth/sign_in_page.dart';
import 'features/auth/local_key_gate_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // Defer the push: errors fired during a Navigator transition / build
    // phase leave the Navigator `_debugLocked`, and pushing inside that
    // window throws an assertion that masks the original error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushCrashScreen(
        appNavigatorKey.currentState,
        CrashRecoveryScreen(message: details.exceptionAsString()),
      );
    });
  };

  // Which mode to start in (#307): a stored school file, an earlier "without
  // a school", or the build's own school — else the first-start choice asks.
  // An install on the build's school gets that school as its file (#308).
  final schoolFiles = SchoolFileStore.appData();
  final prefs = await SharedPreferences.getInstance();
  final build = SchoolConfig.fromBuild;
  final mode = decideStartMode(
    stored: await keepBuildSchoolAsFile(
      stored: await schoolFiles.read(),
      build: build,
      prefs: prefs,
      store: schoolFiles,
    ),
    build: build,
    prefs: prefs,
  );
  if (mode != null) {
    final container = await bootApp(mode);
    runApp(
      UncontrolledProviderScope(container: container, child: const GoalsApp()),
    );
  } else {
    runApp(
      UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const FirstStartApp(boot: bootApp),
      ),
    );
  }
}

/// The app's container for [mode], ready for the first frame: the data
/// behind `CosmosClient.instance`, and the stored sign-in or local profile.
Future<ProviderContainer> bootApp(AppMode mode) async {
  final container = ProviderContainer(
    overrides: [appModeProvider.overrideWithValue(mode)],
  );
  if (mode is StandaloneMode) {
    // Stand-alone (#263): the data lives on the pc. Opened before the first
    // frame, so every `CosmosPaths` handle reads the local storage.
    final dataRoot = await standaloneDataDir(mode);
    final client = CosmosClient.forMode(mode, localDataRoot: dataRoot);
    CosmosClient.overrideInstance(client);
    // The content shipped with the app (#266): goals, lessons, prompts,
    // translations. The school mode reads its own database instead.
    await installCurriculumBundleAtStart(
      client: client,
      localDataRoot: dataRoot,
    );
  } else {
    // The school's database: the build's or the school file's (#307). A
    // build without school data reaches it with the sign-in, whatever the
    // file says (#336).
    CosmosClient.overrideInstance(CosmosClient.forMode(mode));
  }
  // School: the stored sign-in. Stand-alone: the local profile (#264), so a
  // second start goes straight to the app.
  await container.read(authServiceProvider.notifier).tryAcquireTokenSilent();
  return container;
}

/// The first start without a decided mode (#307): the choice, then the app
/// in the chosen mode, booted by [boot] as `main()` boots it.
class FirstStartApp extends ConsumerStatefulWidget {
  const FirstStartApp({super.key, required this.boot});

  final Future<ProviderContainer> Function(AppMode mode) boot;

  @override
  ConsumerState<FirstStartApp> createState() => _FirstStartAppState();
}

class _FirstStartAppState extends ConsumerState<FirstStartApp> {
  ProviderContainer? _app;

  Future<void> _start(AppMode mode) async {
    final app = await widget.boot(mode);
    if (!mounted) {
      app.dispose();
      return;
    }
    setState(() => _app = app);
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) {
      return UncontrolledProviderScope(container: app, child: const GoalsApp());
    }
    final locale = ref.watch(appLocaleProvider);
    final palette = ref.watch(appPaletteProvider);
    AppColors.use(palette);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildAppTheme(palette),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FirstStartPage(onChosen: _start),
    );
  }
}

class GoalsApp extends ConsumerWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // School or stand-alone (#262). Stand-alone has no sign-in: the local
    // profile (#264) is the identity, and its account lives in the local
    // storage (#263).
    final standalone = ref.watch(appModeProvider) is StandaloneMode;
    final identity = ref.watch(authServiceProvider);
    final currentAccount = ref.watch(accountServiceProvider);
    // Whether this build may run at all (#165), asked only once someone is
    // signed in so the sign-in page reads nothing: `AsyncLoading` until the
    // config has answered, then the requirement or `null`.
    final AsyncValue<UpdateRequirement?>? requirement = identity == null
        ? null
        : ref.watch(updateRequirementProvider);
    final hasLocalKey = ref.watch(
      localApiKeyStorageProvider.select((key) => key != null),
    );
    // User override, else the system locale when translated, else English
    // (#23). Resolved once in `appLocaleProvider` so services that need a
    // locale (see `appLocalizationsProvider`) agree with the widget tree.
    final locale = ref.watch(appLocaleProvider);
    // Light / dark (#32). The flat `AppColors.x` tokens read a single active
    // palette, so it has to be installed before anything below builds.
    final palette = ref.watch(appPaletteProvider);
    AppColors.use(palette);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildAppTheme(palette),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          if (identity == null) {
            return standalone
                ? const StandaloneWelcomePage()
                : const SignInPage();
          }

          // Account doc still loading on first sign-in, or the config not yet
          // asked which builds may run (#165) — show a spinner. The second
          // wait is what keeps a build below the minimum from mounting the
          // shell, and starting a session, on a `null` that only means "not
          // read yet".
          if (currentAccount == null ||
              requirement == null ||
              requirement.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Below the school's minimum version (#165): the update screen and
          // nothing else — no shell, no session, nothing to dismiss. Ahead of
          // the key gate on purpose: an out-of-date build must not run,
          // whatever key it would run on.
          final UpdateRequirement? required = requirement.valueOrNull;
          if (required != null) {
            return UpdateRequiredScreen(requirement: required);
          }

          final hasGlobalPermission = currentAccount.mayUseGlobalKey;
          if (!hasGlobalPermission && !hasLocalKey) {
            return const LocalKeyGateScreen();
          }

          // Keyed on the palette so switching theme remounts the shell.
          // Changing `ThemeData` rebuilds everything that reads
          // `Theme.of(context)`, but a `const` widget that reads only
          // `AppColors` is not a theme dependent and its element would be
          // reused with the colours of the old palette. A remount is cheap
          // here — all session state lives in providers above this scope.
          return KeyedSubtree(
            key: ValueKey(palette.brightness),
            child: const AppShell(),
          );
        },
      ),
    );
  }
}
