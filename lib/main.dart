import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/sign_in_page.dart';
import 'home_shell.dart';
import 'theme.dart';
import 'features/auth/local_key_gate_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) =>
            CrashRecoveryScreen(message: details.exceptionAsString()),
      ),
    );
  };

  // Use an explicit container so we can call tryAcquireTokenSilent before
  // the first frame, then hand it off to UncontrolledProviderScope.
  final container = ProviderContainer();
  await container.read(authServiceProvider.notifier).tryAcquireTokenSilent();

  runApp(UncontrolledProviderScope(container: container, child: const GoalsApp()));
}

class GoalsApp extends ConsumerWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final textTheme = createTextTheme(context, "Exo 2", "Exo 2");
    final theme = MaterialTheme(textTheme);

    final identity = ref.watch(authServiceProvider);
    final currentAccount = ref.watch(accountServiceProvider);
    final hasLocalKey = ref.watch(localApiKeyStorageProvider);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Python Course',
      theme: brightness == Brightness.light ? theme.light() : theme.dark(),
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

          return const HomeShell();
        },
      ),
    );
  }
}
