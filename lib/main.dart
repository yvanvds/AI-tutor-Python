import 'package:ai_tutor_python/boot_gate.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/widgets/multi_value_listenable_builder.dart';
import 'package:flutter/material.dart';
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

  DataService.init();

  // Try to restore the previous Entra session before the first frame so a
  // returning user lands on HomeShell instead of flashing SignInPage.
  await DataService.auth.tryAcquireTokenSilent();

  runApp(const GoalsApp());
}

class GoalsApp extends StatelessWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final textTheme = createTextTheme(context, "Exo 2", "Exo 2");
    final theme = MaterialTheme(textTheme);

    return MultiValueListenableBuilder(
      listenables: [
        DataService.auth.currentUser,
        DataService.account.currentAccount,
        DataService.globalConfig.localStorage.isKeyPresent,
      ],
      builder: (context, values) {
        return BootGate(
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Python Course',
            theme: brightness == Brightness.light
                ? theme.light()
                : theme.dark(),
            home: Builder(
              builder: (context) {
                final identity = values[0] as AccountIdentity?;
                if (identity == null) return const SignInPage();

                // Account doc still loading (poll interval can be a few
                // seconds on first sign-in) — show a spinner.
                if (values[1] == null || values[2] == null) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final hasGlobalPermission =
                    (values[1] as Account).mayUseGlobalKey;
                final hasLocalKey = values[2] as bool;

                if (!hasGlobalPermission && !hasLocalKey) {
                  return const LocalKeyGateScreen();
                }

                return const HomeShell();
              },
            ),
          ),
        );
      },
    );
  }
}
