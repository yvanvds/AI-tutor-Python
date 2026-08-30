import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CrashRecoveryScreen extends ConsumerWidget {
  /// [message] is raw diagnostic text (an exception string) shown verbatim.
  const CrashRecoveryScreen({super.key, this.message})
    : _permissionDenied = false;

  /// Cosmos answered 401/403: show the localized permission-denied line.
  const CrashRecoveryScreen.permissionDenied({super.key})
    : message = null,
      _permissionDenied = true;

  final String? message;
  final bool _permissionDenied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The crash screen can mount from a global error handler before the
    // localizations widget is in the tree. Fall back to English in that case.
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final title = l?.crash_title ?? 'We hit a problem';
    final defaultMessage = _permissionDenied
        ? (l?.crash_permissionDenied ?? 'Permission denied while reading data.')
        : l?.crash_defaultMessage ??
              'This can happen after permission or rules changes.\n'
                  'Try resetting the app. You’ll be signed out and caches will be cleared.';
    final resetLabel = l?.crash_resetButton ?? 'Reset app (fix permissions)';
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message ?? defaultMessage, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    await resetAuthAndCacheAndExit(
                      () => ref.read(authServiceProvider.notifier).signOut(),
                    );
                    exit(0);
                  },
                  child: Text(resetLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
