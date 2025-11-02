import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  runApp(const ProviderScope(child: GoalsApp()));
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

    return MaterialApp(
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
    );
  }
}
