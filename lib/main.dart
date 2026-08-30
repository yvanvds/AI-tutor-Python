import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) =>
              CrashRecoveryScreen(message: details.exceptionAsString()),
        ),
      );
    });
  };

  // Use an explicit container so we can call tryAcquireTokenSilent before
  // the first frame, then hand it off to UncontrolledProviderScope.
  final container = ProviderContainer();
  await container.read(authServiceProvider.notifier).tryAcquireTokenSilent();

  runApp(
    UncontrolledProviderScope(container: container, child: const GoalsApp()),
  );
}

class GoalsApp extends ConsumerWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(authServiceProvider);
    final currentAccount = ref.watch(accountServiceProvider);
    final hasLocalKey = ref.watch(localApiKeyStorageProvider);
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
          if (identity == null) return const SignInPage();

          // Account doc still loading on first sign-in — show a spinner.
          if (currentAccount == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
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
