// Writes the `turn_content` docs (#228, CONDUCTOR_POLICY §8.1): one per
// graded turn, with what the student saw, answered and was told.
//
// Best-effort, like the question bank (§2.7): the tutor does not wait for
// the write, a failure is logged and swallowed, never thrown, and a missing
// container leaves the service alone for [kTurnContentRetryAfter] — an
// oefening is never broken or delayed by it. The writes of one app run are
// queued, so they land in the order they were made.
//
// Every write sets `ttl`: the seconds from now until the day in
// `config/global` (`TurnContentKeepUntil`, default 1 July) after the turn,
// at midnight Belgian time. The container has `defaultTtl: -1` — TTL on,
// no default — so a doc without one would be kept forever.
//
// Only written here; read by the teacher's tooling (`evaluate.py trace`).

import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/keep_until.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_content.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the tutor leaves `turn_content` alone after finding the
/// container missing — as for the question bank: not a request per
/// oefening for nothing, and a container created mid-lesson is picked up
/// without a restart.
const Duration kTurnContentRetryAfter = Duration(minutes: 10);

class TurnContentService {
  TurnContentService({
    CosmosContainer? container,
    required this._getUid,
    DateTime Function()? now,
  }) : _containerOverride = container,
       _now = now ?? (() => DateTime.now().toUtc());

  final CosmosContainer? _containerOverride;
  final String? Function() _getUid;
  final DateTime Function() _now;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.turnContent();

  /// The tail of the write queue. Never completes with an error.
  Future<void> _tail = Future<void>.value();

  DateTime? _unavailableUntil;

  /// Writes [content] for the signed-in student, kept until [keepUntil]
  /// (the school's day, `null` for 1 July) after its turn. Never throws;
  /// the returned future is for tests — the tutor does not wait for it.
  Future<void> record(TurnContent content, {KeepUntil? keepUntil}) {
    final run = _tail.then((_) => _write(content, keepUntil));
    _tail = run;
    return run;
  }

  /// Waits for every write queued so far. For tests.
  @visibleForTesting
  Future<void> get idle => _tail;

  Future<void> _write(TurnContent content, KeepUntil? keepUntil) async {
    if (!_available) return;
    try {
      final uid = _getUid();
      if (uid == null) return;
      final day = keepUntil ?? KeepUntil.schoolYearEnd;
      // At the write, not when the doc was put together: Cosmos counts the
      // ttl from the write.
      final now = _now();
      final doc = content.toMap(
        uid: uid,
        keepUntil: day.after(content.turnAt),
        ttl: day.ttlSeconds(at: content.turnAt, now: now),
      );
      await safeCosmos(() => _container.upsert(doc, partitionKey: uid));
    } on CosmosException catch (e) {
      if (e.isContainerNotFound) {
        _unavailableUntil = _now().add(kTurnContentRetryAfter);
        debugPrint(
          'TurnContentService: no `turn_content` container — create it '
          '(README step 3). Nothing is stored for the next '
          '${kTurnContentRetryAfter.inMinutes} minutes. $e',
        );
        return;
      }
      debugPrint('TurnContentService: write ${content.id} failed: $e');
    } catch (e) {
      debugPrint('TurnContentService: write ${content.id} failed: $e');
    }
  }

  bool get _available {
    final until = _unavailableUntil;
    return until == null || !_now().isBefore(until);
  }
}

final turnContentServiceProvider = Provider<TurnContentService>(
  (ref) => TurnContentService(getUid: () => ref.read(authServiceProvider)?.oid),
);
