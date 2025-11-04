import 'package:ai_tutor_python/boot_gate.dart';
import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'firebase_options.dart';
import 'features/auth/sign_in_page.dart';
import 'home_shell.dart';
import 'theme.dart';

// NEW: imports for providers & gate screen
import 'data/account/account_providers.dart'; // myMayUseGlobalKeyProviderStream
import 'data/config/global_config_providers.dart'; // myMayUseGlobalKeyProviderStream
import 'features/auth/local_key_gate_screen.dart'; // LocalKeyGateScreen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    await _connectToFirebaseEmulator();
  }

  await _awaitFreshAuth();

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

  runApp(const ProviderScope(child: GoalsApp()));
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

class GoalsApp extends ConsumerWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final textTheme = createTextTheme(context, "Exo 2", "Exo 2");
    final theme = MaterialTheme(textTheme);

    // Watch global-key permission (live stream)
    final mayUseGlobalKeyAv = ref.watch(myMayUseGlobalKeyProviderStream);
    // Watch presence of local key (refreshes when invalidated by the gate screen)
    final hasLocalKeyAv = ref.watch(localApiKeyExistsProvider);

    return BootGate(
      // checks for Shift key on startup
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'Python Course',
        theme: brightness == Brightness.light ? theme.light() : theme.dark(),
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
            if (mayUseGlobalKeyAv.isLoading || hasLocalKeyAv.isLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // If any errors, show a basic error (you can style this as you like).
            if (mayUseGlobalKeyAv.hasError) {
              return Scaffold(
                body: Center(child: Text('Error: ${mayUseGlobalKeyAv.error}')),
              );
            }
            if (hasLocalKeyAv.hasError) {
              return Scaffold(
                body: Center(child: Text('Error: ${hasLocalKeyAv.error}')),
              );
            }

            final hasGlobalPermission = mayUseGlobalKeyAv.value ?? false;
            final hasLocalKey = hasLocalKeyAv.value ?? false;

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
