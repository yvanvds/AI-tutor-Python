import 'package:ai_tutor_python/create_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'firebase_options.dart';
import 'features/auth/sign_in_page.dart';
import 'home_shell.dart';
import 'theme.dart';

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
    TextTheme textTheme = createTextTheme(context, "Exo 2", "Exo 2");
    MaterialTheme theme = MaterialTheme(textTheme);

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

          // Signed in → hand off to the shell.
          return const HomeShell();
        },
      ),
    );
  }
}
