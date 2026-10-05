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
// Written here, and deleted here when the student resets their progress
// (#232): everything, or one subgoal — the docs next to the `turn_history`
// records the reset deletes. Best-effort as well: the reset of progress,
// beliefs and history never waits on it or fails by it. Never the question
// bank (`questions`): it is kept for next year, also the questions this
// student was the first to get. Read by the teacher's tooling
// (`evaluate.py trace`).

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
  Future<void> record(TurnContent content, {KeepUntil? keepUntil}) =>
      _enqueue(() => _write(content, keepUntil));

  /// Deletes every `turn_content` doc of the signed-in student (#232):
  /// "Reset all progress" takes the content of the oefeningen along with
  /// their `turn_history` records. Queued behind the writes made so far, so
  /// one still on its way is deleted too. Never throws.
  Future<void> deleteAllForCurrentUser() => _enqueue(() => _delete(null));

  /// Deletes the signed-in student's docs on [subgoalId] (#232): the
  /// subgoal of the asked LO, as on the turn record, so what goes is what
  /// the reset of that subgoal deletes from `turn_history`. Queued and
  /// never throws, like [deleteAllForCurrentUser].
  Future<void> deleteAllForSubgoal(String subgoalId) =>
      _enqueue(() => _delete(subgoalId));

  /// Waits for every write and delete queued so far. For tests.
  @visibleForTesting
  Future<void> get idle => _tail;

  Future<void> _enqueue(Future<void> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run;
    return run;
  }

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

  /// Tried even while writes are left alone: a reset is rare, and the
  /// container may have been created since. A missing container has nothing
  /// to delete; a doc already gone (its `ttl` ran out) is skipped; any other
  /// failure stops the delete, logged.
  Future<void> _delete(String? subgoalId) async {
    try {
      final uid = _getUid();
      if (uid == null) return;
      await safeCosmos(() async {
        final docs = await _container.query(
          subgoalId == null
              ? 'SELECT c.id FROM c WHERE c.uid = @uid'
              : 'SELECT c.id FROM c WHERE c.uid = @uid AND c.subgoalId = @sid',
          parameters: {'@uid': uid, '@sid': ?subgoalId},
          partitionKey: uid,
        );
        for (final doc in docs) {
          final id = doc['id'];
          if (id is! String) continue;
          try {
            await _container.delete(id, partitionKey: uid);
          } on CosmosException catch (e) {
            if (e.statusCode != 404 || e.isContainerNotFound) rethrow;
          }
        }
      });
    } on CosmosException catch (e) {
      if (e.isContainerNotFound) {
        _unavailableUntil = _now().add(kTurnContentRetryAfter);
        debugPrint(
          'TurnContentService: no `turn_content` container — nothing to '
          'delete. $e',
        );
        return;
      }
      debugPrint('TurnContentService: delete failed: $e');
    } catch (e) {
      debugPrint('TurnContentService: delete failed: $e');
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
