import 'package:ai_tutor_python/boot_gate.dart';
import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/widgets/multi_value_listenable_builder.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'firebase_options.dart';
import 'features/auth/sign_in_page.dart';
import 'home_shell.dart';
import 'theme.dart';
import 'features/auth/local_key_gate_screen.dart'; // LocalKeyGateScreen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // if (kDebugMode) {
  //   await _connectToFirebaseEmulator();
  // }

  // await _awaitFreshAuth();

  // Global error routing (optional)
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

  runApp(GoalsApp());
}

Future<void> _connectToFirebaseEmulator() async {
  const host = 'localhost';

  // Auth
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);

  // Firestore
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // Optional: disable persistence to avoid conflicts with real DB
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  debugPrint('Connected to Firebase emulators');
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
        DataService.account.currentAccount,
        DataService.globalConfig.localStorage.isKeyPresent,
      ],
      builder: (context, values) {
        return BootGate(
          // checks for Shift key on startup
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Python Course',
            theme: brightness == Brightness.light
                ? theme.light()
                : theme.dark(),
            home: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final user = snap.data;
                if (user == null) return const SignInPage();

                // If either async value is loading, keep a simple loader.
                if (values[0] == null || values[1] == null) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final hasGlobalPermission =
                    values[0] != null && (values[0] as Account).mayUseGlobalKey;
                final hasLocalKey = values[1] as bool;

                // Gate: show LocalKeyGateScreen until user has global permission OR a local key.
                if (!hasGlobalPermission && !hasLocalKey) {
                  return const LocalKeyGateScreen();
                }

                // Signed in & passed the gate → dashboard shell
                return const HomeShell();
              },
            ),
          ),
        );
      },
    );
  }
}

Future<void> _awaitFreshAuth() async {
  final auth = FirebaseAuth.instance;

  // Wait for the first auth emission (null or a User)
  // This makes sure Firebase finished initializing the currentUser.
  await auth.authStateChanges().first;

  final user = auth.currentUser;
  if (user != null) {
    // Ensure the user object and ID token (claims) are up-to-date
    await user.reload();
    await user.getIdToken(true); // <- force refresh claims/permissions
  }
}
