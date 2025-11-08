import 'dart:io';

import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

Future<T> safeFirestore<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') {
      debugPrint('Permission denied error from Firestore: $e');
      // Fire and forget reset

      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => const CrashRecoveryScreen(
            message: 'Permission denied while reading data.',
          ),
        ),
      );
    }
    rethrow;
  }
}

Future<void> resetAuthAndCacheAndExit() async {
  // 1. Sign out (server-side session & tokens)
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    // ignore, we're going nuclear anyway
  }

  // 2. Terminate Firestore so files are no longer held open
  try {
    await FirebaseFirestore.instance.terminate();
  } catch (_) {
    // also fine
  }

  // 3. Delete local Firebase/Firestore caches under LOCALAPPDATA
  try {
    await _deleteWindowsFirebaseCaches();
  } catch (_) {
    // best-effort: failure here shouldn't block exit
  }

  // 4. Bail out — next launch will recreate everything clean
  exit(0);
}

Future<void> _deleteWindowsFirebaseCaches() async {
  if (!Platform.isWindows) return;

  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData == null || localAppData.isEmpty) return;

  // These are the typical culprits you just found:
  final candidates = <Directory>[
    Directory(p.join(localAppData, 'firestore')),
    Directory(p.join(localAppData, 'firebase-heartbeat')),

    // Extra safety: other common Firebase desktop locations
    Directory(p.join(localAppData, 'firebase')),
    Directory(p.join(localAppData, 'google', 'CloudFirestore')),
    Directory(p.join(localAppData, 'google', 'firebase')),
    Directory(p.join(localAppData, 'google', 'firebase_installations')),
  ];

  for (final dir in candidates) {
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Ignore individual failures; some may be in use or protected.
      }
    }
  }
}

/// Lightweight stream guard: on permission-denied, trigger a reset (async)
/// and rethrow so the UI can react (e.g., route to SignInPage).
Stream<T> safeFirestoreStream<T>(Stream<T> source) {
  return source.handleError((error, stack) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      // Fire and forget; don't block the stream’s error pathway.
      // ignore: discarded_futures
      // resetAuthAndCacheAndExit();
      // Let the error continue so your UI (StreamBuilder) can show a fallback.
    }
  });
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
