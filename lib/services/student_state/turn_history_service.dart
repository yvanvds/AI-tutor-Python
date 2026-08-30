// Persists `turn_history` docs (CONDUCTOR_POLICY 8.1). Best-effort writes:
// failures log and continue so a Cosmos blip can't dead-end the student
// flow.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TurnHistoryService {
  TurnHistoryService({
    CosmosContainer? container,
    required String? Function() getUid,
  }) : _containerOverride = container,
       _getUid = getUid;

  final CosmosContainer? _containerOverride;
  final String? Function() _getUid;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.turnHistory();

  String? get _uid => _getUid();

  Future<void> append(PersistedTurnRecord record) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await safeCosmos(
        () => _container.create(record.toMap(uid: uid), partitionKey: uid),
      );
    } catch (e) {
      debugPrint('TurnHistoryService: append failed: $e');
    }
  }

  /// Write a non-graded audit event (CONDUCTOR_POLICY §8.2 audit-trail
  /// signals: empty-objectives blocks, subgoal-deleted redirects).
  /// Synthesises a minimal `PersistedTurnRecord` with the event populated
  /// and otherwise default fields so the dashboard query path is uniform.
  Future<void> appendAudit({
    required String subgoalId,
    required TurnSignalEvent event,
    DateTime? at,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final ts = (at ?? DateTime.now().toUtc()).toUtc();
    final record = PersistedTurnRecord(
      id: CosmosDocId.turnHistory(ts),
      turnAt: ts,
      subgoalId: subgoalId,
      targetLOIds: const [],
      questionType: '',
      difficulty: null,
      isFollowUp: false,
      chainDepth: 0,
      selectionReason: null,
      overallQuality: AnswerQuality.wrong,
      loSignals: const [],
      hadFallback: false,
      appliedSignals: const [],
      calibrationBefore: QuestionDifficulty.medium,
      calibrationAfter: QuestionDifficulty.medium,
      subgoalProgressAfter: 0.0,
      loStatusAfter: const [],
      subgoalAdvanced: false,
      signalEvents: [event],
    );
    await append(record);
  }

  /// Polling stream of unacknowledged-strong-event counts for one student.
  /// Drives the "needs attention" badge on the accounts page.
  Stream<int> watchStrongUnacknowledgedFor(String uid) {
    return safeCosmosStream(
      pollingStream(() => countStrongUnacknowledgedFor(uid)),
    );
  }

  /// Polling stream of recent event-bearing turns for one student.
  Stream<List<PersistedTurnRecord>> watchEventsFor(
    String uid, {
    int take = 50,
  }) {
    return safeCosmosStream(
      pollingStream(() => listEventsFor(uid, take: take)),
    );
  }

  /// Recent strong-or-audit events for one student, newest-first. Used by
  /// the teacher detail drawer.
  Future<List<PersistedTurnRecord>> listEventsFor(
    String uid, {
    int take = 50,
  }) async {
    return safeCosmos(() async {
      final docs = await _container.query(
        // Cosmos doesn't allow ARRAY_LENGTH on a sub-array directly inside
        // WHERE without unwrapping; the cheapest portable filter is
        // IS_DEFINED + non-empty.
        'SELECT * FROM c WHERE c.uid = @uid '
        'AND IS_DEFINED(c.signalEvents) '
        'AND ARRAY_LENGTH(c.signalEvents) > 0 '
        'ORDER BY c.turnAt DESC',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      final out = <PersistedTurnRecord>[];
      for (final doc in docs) {
        out.add(PersistedTurnRecord.fromCosmos(doc));
        if (out.length >= take) break;
      }
      return out;
    });
  }

  /// Count of unacknowledged strong events for one student. Drives the
  /// "needs attention" badge on the accounts page.
  Future<int> countStrongUnacknowledgedFor(String uid) async {
    return safeCosmos(() async {
      // Cosmos NoSQL doesn't expose a server-side filter that drills into
      // an array element's `severity` cheaply across SDK versions; we fetch
      // the unacknowledged event-bearing docs and count strong on the
      // client. Bounded by `take` — strong events are rare per student.
      final docs = await _container.query(
        'SELECT c.signalEvents, c.acknowledgedAt FROM c '
        'WHERE c.uid = @uid '
        'AND (NOT IS_DEFINED(c.acknowledgedAt) OR IS_NULL(c.acknowledgedAt)) '
        'AND IS_DEFINED(c.signalEvents) '
        'AND ARRAY_LENGTH(c.signalEvents) > 0',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      int n = 0;
      for (final doc in docs) {
        final evs = doc['signalEvents'];
        if (evs is! List) continue;
        for (final e in evs) {
          if (e is Map && e['severity'] == 'strong') {
            n += 1;
            break; // count one per turn — same as listing semantics
          }
        }
      }
      return n;
    });
  }

  /// Mark every currently-unacknowledged event-bearing doc for [uid] as
  /// acknowledged. Per CONDUCTOR_POLICY §8.2 acknowledgment is per-student;
  /// the teacher action clears the whole list.
  Future<void> acknowledgeAllFor(String uid) async {
    await safeCosmos(() async {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final docs = await _container.query(
        'SELECT * FROM c WHERE c.uid = @uid '
        'AND (NOT IS_DEFINED(c.acknowledgedAt) OR IS_NULL(c.acknowledgedAt)) '
        'AND IS_DEFINED(c.signalEvents) '
        'AND ARRAY_LENGTH(c.signalEvents) > 0',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      for (final doc in docs) {
        doc['acknowledgedAt'] = nowIso;
        await _container.upsert(doc, partitionKey: uid);
      }
    });
  }

  /// Removes the current user's turn records for one subgoal (issue #25,
  /// granular reset).
  Future<void> deleteAllForSubgoal(String subgoalId) async {
    final uid = _uid;
    if (uid == null) return;
    await safeCosmos(() async {
      final docs = await _container.query(
        'SELECT c.id FROM c WHERE c.uid = @uid AND c.subgoalId = @sid',
        parameters: {'@uid': uid, '@sid': subgoalId},
        partitionKey: uid,
      );
      for (final doc in docs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        await _container.delete(id, partitionKey: uid);
      }
    });
  }

  Future<void> deleteAllForCurrentUser() async {
    final uid = _uid;
    if (uid == null) return;
    await safeCosmos(() async {
      final docs = await _container.query(
        'SELECT c.id FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      for (final doc in docs) {
        final id = doc['id'] as String?;
        if (id == null) continue;
        await _container.delete(id, partitionKey: uid);
      }
    });
  }
}

final turnHistoryServiceProvider = Provider<TurnHistoryService>((ref) {
  return TurnHistoryService(getUid: () => ref.read(authServiceProvider)?.oid);
});
