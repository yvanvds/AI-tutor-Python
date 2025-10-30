import 'package:ai_tutor_python/data/account/account_providers.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'features/dashboard.dart';
import 'firebase_options.dart';
import 'features/auth/sign_in_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: GoalsApp()));
}

class GoalsApp extends ConsumerWidget {
  const GoalsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(accountRepositoryProvider);

    return MaterialApp(
      title: 'Python Course',
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

          // we're signed in
          final accountAsync = ref.watch(myAccountProviderFuture);

          // Build your title from the AsyncValue
          final titleText = accountAsync.maybeWhen(
            data: (acc) {
              final fallback =
                  user.displayName?.split(' ').first ?? user.email ?? 'user';
              return 'Welcome back ${acc?.firstName ?? fallback}, let\'s learn!';
            },
            orElse: () => 'Welcome…', // small placeholder while loading
          );

          return Scaffold(
            appBar: AppBar(
              title: Text(titleText),
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: const Dashboard(),
          );
        },
      ),
    );
  }
}
