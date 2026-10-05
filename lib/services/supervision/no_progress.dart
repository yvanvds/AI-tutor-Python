// The "stuck" alert for the teacher during the lesson (#229,
// CONDUCTOR_POLICY §8.2).
//
// A student who works long on the active subgoal without getting anywhere
// and with mostly wrong answers is stuck. The teacher used to hear it from
// the student; the data showed it already. This check tells the teacher in
// the lesson: a strong `noProgress` event drives the "needs attention"
// badge on the Students page.
//
// It fires on the active subgoal when both hold:
//
// - at least [PolicyConstants.noProgressMinMinutes] since the last moment
//   of progress: an LO newly mastered, a subgoal advance, or the start of
//   the work on this subgoal in this session (the first answer on it after
//   another subgoal or after a pause longer than
//   [PolicyConstants.noProgressSessionGap]);
// - at least [PolicyConstants.noProgressMinBadShare] of the last answers on
//   the subgoal since then not right (wrong or partly right): at most
//   [PolicyConstants.noProgressWindow], at least
//   [PolicyConstants.noProgressMinAnswers], follow-ups included.
//
// Warm-up reviews and rechecks do not count: they are about another
// subgoal. At most once per session and subgoal.
//
// It is a signal for the teacher and nothing else: it writes no belief,
// changes no weight and no grade, and the student never sees it. It runs
// after every graded turn on the student's laptop, off the student's path,
// and is silent when it fails — like the provenance-gap check (#107).

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A student stuck on one subgoal: what the event carries.
@immutable
class NoProgress {
  const NoProgress({
    required this.subgoalId,
    required this.since,
    required this.minutes,
    required this.oefeningen,
    required this.answers,
    required this.notRight,
    required this.calibration,
    this.loId,
    this.mean,
  });

  final String subgoalId;

  /// The last moment of progress: when the clock started.
  final DateTime since;

  /// Whole minutes from [since] to the answer that raised the alert.
  final int minutes;

  /// Questions answered on the subgoal since [since], follow-ups left out.
  final int oefeningen;

  /// The last answers read ([PolicyConstants.noProgressWindow] at most,
  /// follow-ups included), and how many of them were not right.
  final int answers;
  final int notRight;

  /// The level the student was calibrated at after the answer.
  final QuestionDifficulty calibration;

  /// The LO asked most often since [since], and its μ after the answer;
  /// `null` when no question named one.
  final String? loId;
  final double? mean;

  TurnSignalEvent toEvent() => TurnSignalEvent.of(
    TurnSignalEventKind.noProgress,
    details: {
      'subgoalId': subgoalId,
      'since': since.toUtc().toIso8601String(),
      'minutes': minutes,
      'oefeningen': oefeningen,
      'answers': answers,
      'notRight': notRight,
      'loId': ?loId,
      'mean': ?mean,
      'calibration': calibration.name,
    },
  );

  /// The alert a `noProgress` event describes, for the teacher's drawer;
  /// `null` for another kind or details it cannot read.
  static NoProgress? fromEvent(TurnSignalEvent event) {
    if (event.kind != TurnSignalEventKind.noProgress) return null;
    final d = event.details;
    int? count(String key) => switch (d[key]) {
      final num n => n.toInt(),
      _ => null,
    };
    final subgoalId = d['subgoalId'];
    final sinceRaw = d['since'];
    final since = sinceRaw is String ? DateTime.tryParse(sinceRaw) : null;
    final minutes = count('minutes');
    final oefeningen = count('oefeningen');
    final answers = count('answers');
    final notRight = count('notRight');
    if (subgoalId is! String ||
        since == null ||
        minutes == null ||
        oefeningen == null ||
        answers == null ||
        notRight == null ||
        answers <= 0) {
      return null;
    }
    final loId = d['loId'];
    final mean = d['mean'];
    final calibration = d['calibration'];
    return NoProgress(
      subgoalId: subgoalId,
      since: since,
      minutes: minutes,
      oefeningen: oefeningen,
      answers: answers,
      notRight: notRight,
      calibration: QuestionDifficulty.values.firstWhere(
        (q) => q.name == calibration,
        orElse: () => QuestionDifficulty.medium,
      ),
      loId: loId is String && loId.isNotEmpty ? loId : null,
      mean: mean is num ? mean.toDouble() : null,
    );
  }
}

/// Whether [r] is an answer on the subgoal the student was practising: a
/// graded turn, not an audit record, a warm-up review or a recheck.
bool _counts(PersistedTurnRecord r) =>
    r.questionType.isNotEmpty && !r.isWarmUp && !r.isRecheck;

/// The answers of [records] that count, oldest first.
List<PersistedTurnRecord> _answers(List<PersistedTurnRecord> records) => [
  for (final r in records)
    if (_counts(r)) r,
]..sort((a, b) => a.turnAt.compareTo(b.turnAt));

/// When the session of the last answer in [records] started: the first
/// answer after the last pause longer than
/// [PolicyConstants.noProgressSessionGap], or the first one read. `null`
/// when [records] hold no answer.
DateTime? sessionStartOf(List<PersistedTurnRecord> records) {
  final answers = _answers(records);
  if (answers.isEmpty) return null;
  var start = answers.last.turnAt;
  for (var i = answers.length - 1; i > 0; i--) {
    final gap = answers[i].turnAt.difference(answers[i - 1].turnAt);
    if (gap > PolicyConstants.noProgressSessionGap) break;
    start = answers[i - 1].turnAt;
  }
  return start;
}

/// Whether the last answer in [records] — the student's records, oldest
/// first, the answer just graded included — leaves the student stuck on
/// its subgoal (`PolicyConstants.noProgress*`), and how.
///
/// Walks the answers in order (warm-up reviews, rechecks and audit records
/// left out). The clock starts again on the first answer on a subgoal after
/// another subgoal, after a pause longer than
/// [PolicyConstants.noProgressSessionGap], and on an answer that made
/// progress: one that advanced the subgoal, or after which an LO of the
/// subgoal is mastered that no earlier answer on it read left mastered. That
/// answer itself is progress, not one of the answers since. An LO that
/// slips under the bar and comes back is not new; the first answer read on
/// a subgoal is the baseline, and the start of its clock anyway.
NoProgress? detectNoProgress(List<PersistedTurnRecord> records) {
  final answers = _answers(records);
  if (answers.isEmpty) return null;

  DateTime? previousAt;
  String? subgoalId;
  var start = answers.first.turnAt;
  final sinceStart = <PersistedTurnRecord>[];
  final seenMastered = <String, Set<String>>{};
  for (final r in answers) {
    final paused =
        previousAt != null &&
        r.turnAt.difference(previousAt) > PolicyConstants.noProgressSessionGap;
    previousAt = r.turnAt;
    if (paused || r.subgoalId != subgoalId) {
      subgoalId = r.subgoalId;
      start = r.turnAt;
      sinceStart.clear();
    }
    final mastered = {
      for (final s in r.loStatusAfter)
        if (s.mastered) s.loId,
    };
    final seen = seenMastered[r.subgoalId];
    final newlyMastered = seen != null && !seen.containsAll(mastered);
    (seenMastered[r.subgoalId] ??= <String>{}).addAll(mastered);
    if (r.subgoalAdvanced || newlyMastered) {
      start = r.turnAt;
      sinceStart.clear();
      continue;
    }
    sinceStart.add(r);
  }

  final last = answers.last;
  if (sinceStart.isEmpty || !identical(sinceStart.last, last)) return null;
  final elapsed = last.turnAt.difference(start);
  if (elapsed < const Duration(minutes: PolicyConstants.noProgressMinMinutes)) {
    return null;
  }
  final recent = sinceStart.length > PolicyConstants.noProgressWindow
      ? sinceStart.sublist(sinceStart.length - PolicyConstants.noProgressWindow)
      : sinceStart;
  if (recent.length < PolicyConstants.noProgressMinAnswers) return null;
  final notRight = recent
      .where((r) => r.overallQuality != AnswerQuality.correct)
      .length;
  // A share of a small count: compare with some slack, so that e.g. 3 of 6
  // is not ruled out by the last bit.
  const slack = 1e-9;
  if (notRight / recent.length <
      PolicyConstants.noProgressMinBadShare - slack) {
    return null;
  }

  // The LO asked most often since the clock started; of two asked as often,
  // the one asked last.
  final asked = <String, int>{};
  final lastAsked = <String, int>{};
  for (final (i, r) in sinceStart.indexed) {
    if (r.targetLOIds.isEmpty) continue;
    final lo = r.targetLOIds.first;
    asked[lo] = (asked[lo] ?? 0) + 1;
    lastAsked[lo] = i;
  }
  String? loId;
  for (final lo in asked.keys) {
    if (loId == null ||
        asked[lo]! > asked[loId]! ||
        (asked[lo] == asked[loId] && lastAsked[lo]! > lastAsked[loId]!)) {
      loId = lo;
    }
  }
  double? mean;
  for (final s in last.loStatusAfter) {
    if (s.loId == loId) mean = s.mean;
  }

  return NoProgress(
    subgoalId: last.subgoalId,
    since: start,
    minutes: elapsed.inMinutes,
    oefeningen: sinceStart.where((r) => !r.isFollowUp).length,
    answers: recent.length,
    notRight: notRight,
    calibration: last.calibrationAfter,
    loId: loId,
    mean: mean,
  );
}

/// Runs the check after a graded turn and writes the event (#229).
class NoProgressService {
  NoProgressService({required this._turns});

  final TurnHistoryService _turns;

  /// `uid/subgoalId/session start` of every alert this app raised: what
  /// keeps two answers in quick succession from both raising one before
  /// the first one's record can be read back.
  final Set<String> _raised = {};

  /// Checks the subgoal of [turn] — the graded turn of [uid] that was just
  /// recorded — and writes a `noProgress` event, as an audit record on that
  /// subgoal (`TurnHistoryService.appendAudit`), when the student is stuck
  /// on it. Returns the alert written, or `null`.
  ///
  /// At most once per session and subgoal: an alert already raised on the
  /// subgoal since the session started is not raised again, whatever
  /// happened since. Best-effort and silent: the student is never told,
  /// and a failure only costs the teacher a signal.
  ///
  /// One read of the student's records of the last
  /// [PolicyConstants.noProgressLookback] per graded turn; a warm-up review
  /// or a recheck is not checked, the next answer on the active subgoal is.
  Future<NoProgress?> checkAfter({
    required String uid,
    required PersistedTurnRecord turn,
  }) async {
    try {
      if (!_counts(turn)) return null;
      final stored = await _turns.listSince(
        uid,
        from: turn.turnAt.subtract(PolicyConstants.noProgressLookback),
      );
      // The write of [turn] runs alongside this read: take the one in hand.
      final records = [
        for (final r in stored)
          if (r.id != turn.id) r,
        turn,
      ]..sort((a, b) => a.turnAt.compareTo(b.turnAt));
      final alert = detectNoProgress(records);
      if (alert == null || alert.subgoalId != turn.subgoalId) return null;
      final sessionStart = sessionStartOf(records)!;
      final key = '$uid/${alert.subgoalId}/${sessionStart.toIso8601String()}';
      if (_raised.contains(key) ||
          _alreadyRaised(records, alert.subgoalId, sessionStart)) {
        return null;
      }
      _raised.add(key);
      await _turns.appendAudit(
        subgoalId: alert.subgoalId,
        event: alert.toEvent(),
      );
      return alert;
    } catch (e) {
      debugPrint('NoProgressService: check failed: $e');
      return null;
    }
  }

  /// Whether [records] hold an alert on [subgoalId] raised in the session
  /// that started at [sessionStart]: one whose clock started in it. Read by
  /// the alert's own `since`, not by when its record was written.
  static bool _alreadyRaised(
    List<PersistedTurnRecord> records,
    String subgoalId,
    DateTime sessionStart,
  ) {
    for (final r in records) {
      for (final e in r.signalEvents) {
        final raised = NoProgress.fromEvent(e);
        if (raised != null &&
            raised.subgoalId == subgoalId &&
            !raised.since.isBefore(sessionStart)) {
          return true;
        }
      }
    }
    return false;
  }
}

final noProgressServiceProvider = Provider<NoProgressService>(
  (ref) => NoProgressService(turns: ref.watch(turnHistoryServiceProvider)),
);
