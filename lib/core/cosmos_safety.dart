// Cosmos safety wrappers. Three concerns:
//
//   1. `safeCosmos` — wraps a one-shot async op; on auth failure (401/403)
//      pushes the CrashRecoveryScreen so the user can reset and re-sign-in.
//   2. `safeCosmosStream` — absorbs errors flowing through a polling
//      stream (logs them, keeps the last good value on screen). The polling
//      source keeps ticking, so a transient blip self-heals on the next
//      fetch instead of flipping every StreamBuilder into an error state.
//   3. `pollingStream` — periodic-fetch stream. Cosmos has a change feed but
//      consuming it from a desktop client is awkward; we poll on a fixed
//      cadence instead.
//
// Polling cadence and 429 retry policy are decided here, once. Don't
// relitigate inside individual services.

import 'dart:async';
import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Default polling cadence. Tuned for one global rate — fast enough that
/// teacher-side edits to goals/instructions show up "soon", slow enough that
/// it isn't a load problem with serverless RU/s billing.
const Duration kCosmosPollInterval = Duration(seconds: 5);

/// One-shot guard. On 401/403 routes to the recovery screen and rethrows;
/// the caller's UI still sees the failure so it can render an error state.
Future<T> safeCosmos<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on CosmosException catch (e) {
    if (e.isAuthError) {
      debugPrint('safeCosmos: auth error from Cosmos: $e');
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => const CrashRecoveryScreen.permissionDenied(),
        ),
      );
    }
    rethrow;
  }
}

/// Stream guard. `Stream.handleError` *absorbs* the error when the handler
/// returns normally, so consumers never see it: they keep the last value
/// and pick up the next successful poll. Auth errors have already routed
/// to the recovery screen inside `safeCosmos` by the time they get here.
/// Every error is logged (#7) — before, anything that wasn't a 401/403/429
/// vanished without a trace.
Stream<T> safeCosmosStream<T>(Stream<T> source) {
  return source.handleError((Object error, StackTrace stack) {
    final code = error is CosmosException
        ? '${error.statusCode}'
        : 'non-Cosmos';
    debugPrint('safeCosmosStream: $code error absorbed: $error');
  });
}

/// Polls [fetch] on [interval], emitting each result on the returned stream.
///
/// Contract:
///   - The first emission happens **synchronously after subscribe**, not
///     after one full interval. Goal-tree screens assume a value within the
///     first frame; without this they'd flash a spinner on every navigation.
///   - Errors thrown by [fetch] surface on the stream as errors but do NOT
///     stop polling — a transient 429 or network blip shouldn't kill the
///     subscription.
///   - Single-subscription stream. Cancelling the subscription cancels the
///     timer and aborts any in-flight fetch result.
///   - If a fetch is still running when the timer fires, the tick is
///     skipped — no overlapping requests per stream.
///
/// Services compose this with `safeCosmos` inside the [fetch] closure when
/// they want auth-error routing:
///
///     pollingStream(() => safeCosmos(() => container.query(...)))
Stream<T> pollingStream<T>(
  Future<T> Function() fetch, {
  Duration interval = kCosmosPollInterval,
}) {
  late StreamController<T> controller;
  Timer? timer;
  bool cancelled = false;
  bool inFlight = false;

  Future<void> tick() async {
    if (cancelled || inFlight) return;
    inFlight = true;
    try {
      final value = await fetch();
      if (!cancelled) controller.add(value);
    } catch (error, stack) {
      if (!cancelled) controller.addError(error, stack);
    } finally {
      inFlight = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      tick();
      timer = Timer.periodic(interval, (_) => tick());
    },
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      timer = null;
    },
  );

  return controller.stream;
}

/// Azure-aware nuke-and-restart, called from `CrashRecoveryScreen`.
Future<void> resetAuthAndCacheAndExit([
  Future<void> Function()? signOut,
]) async {
  if (signOut != null) {
    try {
      await signOut();
    } catch (e) {
      debugPrint('resetAuthAndCacheAndExit: signOut threw: $e');
    }
  }

  // No local Cosmos response cache today. If/when we add one, wipe it here.

  exit(0);
}
