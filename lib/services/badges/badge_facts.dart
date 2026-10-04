// What the badges are computed from (#220): one pass over the student's
// `turn_history`, plus the goals and the lesson times of their class.
//
// Pure: no Cosmos, no clock, no providers — the same records give the same
// counts, which is what lets every badge work with hindsight (the first start
// after the release finds everything the history already earned) and lets a
// test pin each rule on a handful of records. The badges themselves are in
// `badge_catalog.dart`; each reads one number from [BadgeFacts].
//
// Words used below, as the teacher uses them:
//
//   - a graded record: a turn record with a question type — not an audit
//     stub (`TurnHistoryService.appendAudit`);
//   - an oefening: a graded record that is not a follow-up and has a
//     subgoal — what `oefeningCount` counts since #217 and
//     `tooling/xp/backfill.py` counts before it;
//   - lesson time: the rule of #219 — recorded `supervised`, or in a lesson
//     of the student's class, 10 minutes before and after included. An old
//     `home` record in lesson time counts as lesson.
//
// Times of day are the laptop's local time, as the lessons are (#218).

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter/foundation.dart';

/// Whether a moment falls in a lesson of the student's class (#219):
/// `ClassList.isDuringLesson(className, at, margin: …)`.
typedef LessonTimeCheck = bool Function(DateTime at);

/// How far the mastery of one hoofddoel is: its non-optional LOs mastered,
/// of all of them.
typedef ExpertProgress = ({int mastered, int total});

/// How long a question has to be on screen for "Rome is ook niet op één dag
/// gebouwd": more than this, then a right answer.
const Duration kRomeMinimum = Duration(minutes: 5);

/// How many wrong answers in a row a "Comeback" needs before the right one.
const int kComebackWrongRun = 3;

@immutable
class BadgeFacts {
  const BadgeFacts({
    this.oefeningen = 0,
    this.correctOefeningen = 0,
    this.homeOefeningen,
    this.lessonWeeks,
    this.hardCorrect = 0,
    this.bestStreak = 0,
    this.correctByType = const {},
    this.masteredLos = 0,
    this.milestones = 0,
    this.warmUpCorrect = 0,
    this.recheckCorrect = 0,
    this.transferCredits = 0,
    this.comebacks = 0,
    this.wrongToRight = 0,
    this.hintHits = 0,
    this.persevered = 0,
    this.toughest = 0,
    this.experts,
    this.earlyBird = 0,
    this.nightOwl = 0,
    this.weekend = 0,
    this.fridayAfternoonCorrect = 0,
    this.piMinute = 0,
    this.piDay = 0,
    this.halloween = 0,
    this.ownQuestions = 0,
    this.backToFinished = 0,
    this.keyDisputes = 0,
    this.slowCorrect = 0,
  });

  /// No history at all.
  static const BadgeFacts empty = BadgeFacts();

  /// Oefeningen made, right or wrong.
  final int oefeningen;

  /// Oefeningen answered right.
  final int correctOefeningen;

  /// Oefeningen outside lesson time; `null` when the student's class has no
  /// lessons (or they are not known): then nobody can tell, and nothing is
  /// awarded on it.
  final int? homeOefeningen;

  /// Weeks (ISO, local time) with at least one oefening in lesson time, not
  /// necessarily one after the other; `null` as for [homeOefeningen].
  final int? lessonWeeks;

  /// Oefeningen on `hard` answered right.
  final int hardCorrect;

  /// The longest run of oefeningen answered right, one after the other.
  final int bestStreak;

  /// Per question type (`ChatRequestType` name), oefeningen answered right.
  final Map<String, int> correctByType;

  /// LOs mastered at some point (a turn record's status said so), each once.
  final int masteredLos;

  /// Subgoals the student was moved past (`subgoalAdvanced`), each once.
  final int milestones;

  /// Warm-up questions (#102) answered right.
  final int warmUpCorrect;

  /// Recheck questions (#187) answered right.
  final int recheckCorrect;

  /// Transfer credits (#101): an earlier LO used right in new code.
  final int transferCredits;

  /// Right answers after at least [kComebackWrongRun] wrong ones in a row.
  final int comebacks;

  /// Follow-ups answered right after the answer before was not.
  final int wrongToRight;

  /// Oefeningen answered right after a hint on the same one (`usage`).
  final int hintHits;

  /// LOs that were stuck and mastered afterwards.
  final int persevered;

  /// The most oefeningen on one LO before it was mastered.
  final int toughest;

  /// Per hoofddoel id, its non-optional LOs mastered of all of them; `null`
  /// when the goals are not known.
  final Map<String, ExpertProgress>? experts;

  /// Oefeningen from 4:00 to before 8:00.
  final int earlyBird;

  /// Oefeningen from 22:00 to before 4:00.
  final int nightOwl;

  /// Oefeningen on a Saturday or a Sunday.
  final int weekend;

  /// Right answers on a Friday from 15:00 on.
  final int fridayAfternoonCorrect;

  /// Oefeningen at 15:14.
  final int piMinute;

  /// Oefeningen on 14 March.
  final int piDay;

  /// Oefeningen on 31 October.
  final int halloween;

  /// Records whose calls include one the student started with a question of
  /// their own (`UsageCallKind.dialogue`).
  final int ownQuestions;

  /// Ordinary oefeningen — no warm-up, no recheck — on a subgoal the
  /// student had been moved past before.
  final int backToFinished;

  /// Records on which the grader said the answer key is wrong (#198).
  final int keyDisputes;

  /// Oefeningen answered right more than [kRomeMinimum] after they were
  /// asked.
  final int slowCorrect;

  /// The fewest right answers over [types]: each of them at least this
  /// often.
  int correctOnEach(Iterable<String> types) {
    var least = -1;
    for (final type in types) {
      final n = correctByType[type] ?? 0;
      if (least < 0 || n < least) least = n;
    }
    return least < 0 ? 0 : least;
  }

  /// Counts the facts in [records] — any order, audit stubs and all; only
  /// the graded ones count. [goals] (every goal, roots and subgoals) gives
  /// the "Kenner van …" progress; [inLesson] the lesson time of the
  /// student's class, `null` when it has none.
  factory BadgeFacts.from({
    required Iterable<PersistedTurnRecord> records,
    List<Goal>? goals,
    LessonTimeCheck? inLesson,
  }) {
    final graded =
        records.where((r) => r.questionType.isNotEmpty).toList(growable: false)
          ..sort((a, b) {
            final byTime = a.turnAt.compareTo(b.turnAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });

    var oefeningen = 0;
    var correct = 0;
    var home = 0;
    final weeks = <int>{};
    var hard = 0;
    var streak = 0;
    var bestStreak = 0;
    final byType = <String, int>{};
    var warmUp = 0;
    var recheck = 0;
    var transfers = 0;
    var wrongRun = 0;
    var comebacks = 0;
    var wrongToRight = 0;
    var hintHits = 0;
    var earlyBird = 0;
    var nightOwl = 0;
    var weekend = 0;
    var friday = 0;
    var piMinute = 0;
    var piDay = 0;
    var halloween = 0;
    var ownQuestions = 0;
    var backToFinished = 0;
    var disputes = 0;
    var slow = 0;

    // Mastery, per `subgoal/lo`: when first mastered (record index),
    // whether it was stuck before that.
    final firstMastered = <String, int>{};
    final stuckBefore = <String>{};
    var persevered = 0;
    // Subgoals moved past, with the record index it happened at.
    final advancedAt = <String, int>{};

    PersistedTurnRecord? previous;
    for (var i = 0; i < graded.length; i++) {
      final r = graded[i];
      final isCorrect = r.overallQuality == AnswerQuality.correct;
      final calls = r.usage?.byCall ?? const <UsageCallKind, TokenUsage>{};
      if (calls.containsKey(UsageCallKind.dialogue)) ownQuestions++;
      if (r.keyDisputed) disputes++;
      transfers += r.transferCredits.length;

      if (r.isFollowUp &&
          isCorrect &&
          previous != null &&
          previous.overallQuality != AnswerQuality.correct) {
        wrongToRight++;
      }

      final isOefening = !r.isFollowUp && r.subgoalId.isNotEmpty;
      if (isOefening) {
        oefeningen++;
        final local = r.turnAt.toLocal();
        final lesson =
            r.provenance == EvidenceProvenance.supervised ||
            (inLesson?.call(r.turnAt) ?? false);
        if (lesson) {
          weeks.add(_isoWeekKey(local));
        } else {
          home++;
        }
        if (local.hour >= 4 && local.hour < 8) earlyBird++;
        if (local.hour >= 22 || local.hour < 4) nightOwl++;
        if (local.weekday >= DateTime.saturday) weekend++;
        if (local.hour == 15 && local.minute == 14) piMinute++;
        if (local.month == 3 && local.day == 14) piDay++;
        if (local.month == 10 && local.day == 31) halloween++;
        if (!r.isWarmUp && !r.isRecheck && (advancedAt[r.subgoalId] ?? i) < i) {
          backToFinished++;
        }

        if (isCorrect) {
          correct++;
          streak++;
          if (streak > bestStreak) bestStreak = streak;
          byType[r.questionType] = (byType[r.questionType] ?? 0) + 1;
          if (r.difficulty == QuestionDifficulty.hard) hard++;
          if (r.isWarmUp) warmUp++;
          if (r.isRecheck) recheck++;
          if (wrongRun >= kComebackWrongRun) comebacks++;
          if (calls.containsKey(UsageCallKind.hint)) hintHits++;
          if (local.weekday == DateTime.friday && local.hour >= 15) friday++;
          final asked = r.askedAt;
          if (asked != null && r.turnAt.difference(asked) > kRomeMinimum) {
            slow++;
          }
          wrongRun = 0;
        } else {
          streak = 0;
          wrongRun = r.overallQuality == AnswerQuality.wrong ? wrongRun + 1 : 0;
        }
      }

      // The statuses and the advance are about the subgoal the student was
      // on: the active one, which a warm-up or a recheck names apart.
      final statusSubgoal = r.activeSubgoalId ?? r.subgoalId;
      for (final s in r.loStatusAfter) {
        final key = '$statusSubgoal/${s.loId}';
        if (firstMastered.containsKey(key)) continue;
        if (s.mastered) {
          firstMastered[key] = i;
          if (stuckBefore.contains(key)) persevered++;
        } else if (s.stuck) {
          stuckBefore.add(key);
        }
      }
      if (r.subgoalAdvanced && statusSubgoal.isNotEmpty) {
        advancedAt.putIfAbsent(statusSubgoal, () => i);
      }
      previous = r;
    }

    // "Taaie": per mastered LO, the oefeningen that asked it up to the one
    // it was mastered on.
    var toughest = 0;
    for (final entry in firstMastered.entries) {
      final slash = entry.key.indexOf('/');
      final subgoalId = entry.key.substring(0, slash);
      final loId = entry.key.substring(slash + 1);
      var asked = 0;
      for (var i = 0; i <= entry.value; i++) {
        final r = graded[i];
        if (r.isFollowUp || r.subgoalId != subgoalId) continue;
        if (r.targetLOIds.contains(loId)) asked++;
      }
      if (asked > toughest) toughest = asked;
    }

    return BadgeFacts(
      oefeningen: oefeningen,
      correctOefeningen: correct,
      homeOefeningen: inLesson == null ? null : home,
      lessonWeeks: inLesson == null ? null : weeks.length,
      hardCorrect: hard,
      bestStreak: bestStreak,
      correctByType: Map.unmodifiable(byType),
      masteredLos: firstMastered.length,
      milestones: advancedAt.length,
      warmUpCorrect: warmUp,
      recheckCorrect: recheck,
      transferCredits: transfers,
      comebacks: comebacks,
      wrongToRight: wrongToRight,
      hintHits: hintHits,
      persevered: persevered,
      toughest: toughest,
      experts: goals == null
          ? null
          : _expertProgress(goals, firstMastered.keys.toSet()),
      earlyBird: earlyBird,
      nightOwl: nightOwl,
      weekend: weekend,
      fridayAfternoonCorrect: friday,
      piMinute: piMinute,
      piDay: piDay,
      halloween: halloween,
      ownQuestions: ownQuestions,
      backToFinished: backToFinished,
      keyDisputes: disputes,
      slowCorrect: slow,
    );
  }

  /// Per hoofddoel: its non-optional subgoals' non-optional LOs, and how
  /// many of them are in [mastered] (`subgoal/lo` keys). A hoofddoel with no
  /// such LO has nothing to master and is left out.
  static Map<String, ExpertProgress> _expertProgress(
    List<Goal> goals,
    Set<String> mastered,
  ) {
    final out = <String, ExpertProgress>{};
    for (final root in goals.where((g) => g.parentId == null)) {
      var total = 0;
      var done = 0;
      for (final sub in goals) {
        if (sub.parentId != root.id || sub.optional) continue;
        for (final lo in sub.objectives) {
          if (lo.optional) continue;
          total++;
          if (mastered.contains('${sub.id}/${lo.id}')) done++;
        }
      }
      if (total > 0) out[root.id] = (mastered: done, total: total);
    }
    return Map.unmodifiable(out);
  }
}

/// The ISO week of [local]'s date as `year * 100 + week`: Monday to Sunday,
/// week 1 the one with the year's first Thursday. Counted on the calendar
/// date in UTC, so a clock change inside the week does not shift a day.
int _isoWeekKey(DateTime local) {
  final date = DateTime.utc(local.year, local.month, local.day);
  final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
  final week = thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
  return thursday.year * 100 + week;
}

/// [isoWeekKey] for tests.
@visibleForTesting
int isoWeekKeyOf(DateTime local) => _isoWeekKey(local);
