import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The crash screen on top, while it is up.
Route<void>? _shownCrashRoute;

/// Pushes [screen] on [navigator], unless a crash screen is already up: an
/// error that repeats (on every key, every frame) shows one screen rather
/// than a stack of them (#331).
void pushCrashScreen(NavigatorState? navigator, CrashRecoveryScreen screen) {
  if (navigator == null || (_shownCrashRoute?.isActive ?? false)) return;
  final route = MaterialPageRoute<void>(builder: (_) => screen);
  _shownCrashRoute = route;
  navigator.push(route);
}

/// What the app shows when something goes wrong.
///
/// An error in the app itself ([CrashRecoveryScreen.new]) says so, with the
/// error's own text beneath, and leads back to the app: the app is usually
/// still fine, and resetting does not help (#331). A Cosmos 401/403
/// ([CrashRecoveryScreen.permissionDenied]) offers the reset, which signs
/// out and closes the app.
class CrashRecoveryScreen extends ConsumerWidget {
  /// [message] is raw diagnostic text (an exception string), shown verbatim
  /// beneath the explanation.
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
    final detail = message;
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
                if (_permissionDenied) ...[
                  Text(
                    l?.crash_permissionDenied ??
                        'Permission denied while reading data.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      await resetAuthAndCacheAndExit(
                        () => ref.read(authServiceProvider.notifier).signOut(),
                      );
                      exit(0);
                    },
                    child: Text(
                      l?.crash_resetButton ?? 'Reset app (fix permissions)',
                    ),
                  ),
                ] else ...[
                  Text(
                    l?.crash_errorMessage ??
                        'The app ran into an error. Go back and carry on. '
                            'If it keeps happening, close the app and start '
                            'it again.',
                    textAlign: TextAlign.center,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 12),
                    // Selectable, for a bug report or a message to the
                    // teacher.
                    SelectableText(
                      detail,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l?.crash_backButton ?? 'Back to the app'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
