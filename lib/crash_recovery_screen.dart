import 'dart:io';

import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:flutter/material.dart';

class CrashRecoveryScreen extends StatelessWidget {
  const CrashRecoveryScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_rounded, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'We hit a problem',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message ??
                      'This can happen after permission or rules changes.\n'
                          'Try resetting the app. You’ll be signed out and caches will be cleared.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    await resetAuthAndCacheAndExit();
                    exit(0);

                    // if (context.mounted) {
                    //   // After signOut, your auth StreamBuilder will land on SignInPage.
                    //   appNavigatorKey.currentState?.pushAndRemoveUntil(
                    //     MaterialPageRoute(builder: (_) => const SignInPage()),
                    //     (r) => false,
                    //   );
                    // }
                  },
                  child: const Text('Reset app (fix permissions)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
