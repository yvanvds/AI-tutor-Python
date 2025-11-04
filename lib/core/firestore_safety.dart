import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

Future<void> resetAuthAndCache() async {
  await FirebaseFirestore.instance.terminate();
  await FirebaseFirestore.instance.clearPersistence();
  await FirebaseAuth.instance.signOut();
  // If you store tokens/flags in secure storage or shared prefs, clear them here too.
}

/// Lightweight stream guard: on permission-denied, trigger a reset (async)
/// and rethrow so the UI can react (e.g., route to SignInPage).
Stream<T> safeFirestoreStream<T>(Stream<T> source) {
  return source.handleError((error, stack) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      // Fire and forget; don't block the stream’s error pathway.
      // ignore: discarded_futures
      resetAuthAndCache();
      // Let the error continue so your UI (StreamBuilder) can show a fallback.
    }
  });
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
