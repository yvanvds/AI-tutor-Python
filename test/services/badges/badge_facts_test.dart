// Issue #220 — the facts the badges are counted from, one rule at a time, on
// a handful of turn records. The September numbers the tiers were set on
// were counted with these same definitions (an oefening: graded, not a
// follow-up, with a subgoal — #217's), so a rule that drifts here would put
// every tier off.
//
// Times of day are built in local time and stored as UTC, as the app stores
// them, so these hold on any machine's time zone.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// A weekday morning in September, local time.
final DateTime _monday = DateTime(2026, 9, 14, 10);

var _n = 0;

PersistedTurnRecord _rec({
  DateTime? at,
  String subgoal = 's1',
  List<String> los = const ['lo1'],
  String type = 'mcQuestion',
  QuestionDifficulty? difficulty = QuestionDifficulty.medium,
  bool followUp = false,
  AnswerQuality quality = AnswerQuality.correct,
  bool warmUp = false,
  bool recheck = false,
  String? active,
  EvidenceProvenance provenance = EvidenceProvenance.home,
  Set<UsageCallKind> calls = const {},
  int transfers = 0,
  List<TurnLoStatus> status = const [],
  bool advanced = false,
  bool disputed = false,
  DateTime? askedAt,
}) {
  _n++;
  final turnAt = (at ?? _monday.add(Duration(minutes: _n))).toUtc();
  return PersistedTurnRecord(
    id: 't${_n.toString().padLeft(4, '0')}',
    turnAt: turnAt,
    subgoalId: subgoal,
    targetLOIds: los,
    questionType: type,
    difficulty: difficulty,
    isFollowUp: followUp,
    chainDepth: followUp ? 1 : 0,
    isWarmUp: warmUp,
    isRecheck: recheck,
    activeSubgoalId: active,
    selectionReason: null,
    overallQuality: quality,
    loSignals: const [],
    hadFallback: false,
    appliedSignals: const [],
    provenance: provenance,
    usage: calls.isEmpty
        ? null
        : TurnUsage(byCall: {for (final c in calls) c: TokenUsage.zero}),
    transferCredits: [
      for (var i = 0; i < transfers; i++)
        TurnTransferCredit(subgoalId: 's0', loId: 'old$i', alphaDelta: 0.5),
    ],
    calibrationBefore: QuestionDifficulty.medium,
    calibrationAfter: QuestionDifficulty.medium,
    subgoalProgressAfter: 0,
    loStatusAfter: status,
    subgoalAdvanced: advanced,
    keyDisputed: disputed,
    askedAt: askedAt?.toUtc(),
  );
}

TurnLoStatus _status(String lo, {bool mastered = false, bool stuck = false}) =>
    TurnLoStatus(
      loId: lo,
      mean: mastered ? 0.9 : 0.4,
      evidence: 8,
      mastered: mastered,
      stuck: stuck,
    );

BadgeFacts _facts(
  List<PersistedTurnRecord> records, {
  List<Goal>? goals,
  LessonTimeCheck? inLesson,
}) => BadgeFacts.from(records: records, goals: goals, inLesson: inLesson);

void main() {
  setUp(() => _n = 0);

  group('oefeningen (#217\'s definition)', () {
    test('a graded answer that is no follow-up and has a subgoal; right or '
        'wrong', () {
      final f = _facts([
        _rec(),
        _rec(quality: AnswerQuality.wrong),
        _rec(quality: AnswerQuality.partial),
        _rec(followUp: true),
        _rec(subgoal: ''),
        // An audit stub: no question asked.
        _rec(type: ''),
      ]);
      expect(f.oefeningen, 3);
      expect(f.correctOefeningen, 1);
    });

    test('records in any order count the same', () {
      final records = [_rec(quality: AnswerQuality.wrong), _rec(), _rec()];
      expect(
        _facts(records.reversed.toList()).bestStreak,
        _facts(records).bestStreak,
      );
      expect(_facts(records.reversed.toList()).bestStreak, 2);
    });
  });

  group('lesson time (#219): Thuiswerker and Lesweken', () {
    test('without lesson times nobody can tell: both unknown', () {
      final f = _facts([_rec(), _rec()]);
      expect(f.homeOefeningen, isNull);
      expect(f.lessonWeeks, isNull);
    });

    test('recorded supervised, or a home record in lesson time, is lesson; '
        'the rest is home; weeks count once', () {
      bool lessonHour(DateTime at) => at.toLocal().hour == 10;
      final f = _facts([
        // Lesson week 1: one recorded supervised (any hour), one old `home`
        // record in the lesson hour.
        _rec(
          at: DateTime(2026, 9, 14, 13),
          provenance: EvidenceProvenance.supervised,
        ),
        _rec(at: DateTime(2026, 9, 16, 10, 5)),
        // Home, same week.
        _rec(at: DateTime(2026, 9, 16, 19)),
        // Lesson week 2.
        _rec(at: DateTime(2026, 9, 22, 10, 30)),
        // A follow-up in lesson time in week 3: no oefening, no week.
        _rec(at: DateTime(2026, 9, 29, 10, 30), followUp: true),
        // Home, week 3.
        _rec(at: DateTime(2026, 10, 3, 9)),
      ], inLesson: lessonHour);
      expect(f.homeOefeningen, 2);
      expect(f.lessonWeeks, 2);
    });

    test('ISO weeks: Monday to Sunday, across the clock change and the new '
        'year', () {
      // 25 October 2026 is the Sunday the clocks go back.
      expect(
        isoWeekKeyOf(DateTime(2026, 10, 26)),
        isoWeekKeyOf(DateTime(2026, 11, 1, 23, 30)),
      );
      expect(
        isoWeekKeyOf(DateTime(2026, 10, 25, 23)),
        isNot(isoWeekKeyOf(DateTime(2026, 10, 26))),
      );
      // 2026 starts on a Thursday: it has a week 53, which runs into 2027.
      expect(isoWeekKeyOf(DateTime(2026, 12, 31)), 202653);
      expect(isoWeekKeyOf(DateTime(2027, 1, 3)), 202653);
      expect(isoWeekKeyOf(DateTime(2027, 1, 4)), 202701);
      expect(isoWeekKeyOf(DateTime(2026, 1, 1)), 202601);
    });
  });

  group('answers', () {
    test('hard: right oefeningen on hard only', () {
      final f = _facts([
        _rec(difficulty: QuestionDifficulty.hard),
        _rec(difficulty: QuestionDifficulty.hard, quality: AnswerQuality.wrong),
        _rec(difficulty: QuestionDifficulty.hard, followUp: true),
        _rec(),
      ]);
      expect(f.hardCorrect, 1);
    });

    test('the best run of right oefeningen: a wrong or partial one breaks '
        'it, a follow-up does not count either way', () {
      final f = _facts([
        _rec(),
        _rec(),
        _rec(quality: AnswerQuality.partial),
        _rec(),
        _rec(followUp: true, quality: AnswerQuality.wrong),
        _rec(),
        _rec(),
        _rec(quality: AnswerQuality.wrong),
      ]);
      expect(f.bestStreak, 3);
    });

    test('per question type, and the weakest of several', () {
      final f = _facts([
        _rec(type: 'completeCodeQuestion'),
        _rec(type: 'completeCodeQuestion'),
        _rec(type: 'explainCodeQuestion'),
        _rec(type: 'writeCodeQuestion', quality: AnswerQuality.wrong),
        _rec(type: 'mcQuestion'),
      ]);
      expect(f.correctByType['completeCodeQuestion'], 2);
      expect(f.correctByType['explainCodeQuestion'], 1);
      expect(f.correctByType['writeCodeQuestion'], isNull);
      expect(
        f.correctOnEach(['completeCodeQuestion', 'explainCodeQuestion']),
        1,
      );
      expect(f.correctOnEach(['completeCodeQuestion', 'writeCodeQuestion']), 0);
    });

    test('warm-up and recheck questions answered right', () {
      final f = _facts([
        _rec(warmUp: true, subgoal: 's0', active: 's1'),
        _rec(warmUp: true, quality: AnswerQuality.wrong),
        _rec(recheck: true),
        _rec(recheck: true),
      ]);
      expect(f.warmUpCorrect, 1);
      expect(f.recheckCorrect, 2);
    });

    test('transfer credits add up over the records', () {
      expect(
        _facts([_rec(transfers: 2), _rec(transfers: 1)]).transferCredits,
        3,
      );
    });

    test('a comeback is a right answer after three wrong ones in a row; a '
        'partial one breaks the run', () {
      final w = AnswerQuality.wrong;
      expect(
        _facts([
          _rec(quality: w),
          _rec(quality: w),
          _rec(quality: w),
          _rec(),
          _rec(),
        ]).comebacks,
        1,
      );
      expect(
        _facts([
          _rec(quality: w),
          _rec(quality: w),
          _rec(quality: AnswerQuality.partial),
          _rec(quality: w),
          _rec(),
        ]).comebacks,
        0,
      );
      expect(
        _facts([
          for (var i = 0; i < 5; i++) _rec(quality: w),
          _rec(),
          for (var i = 0; i < 3; i++) _rec(quality: w),
          _rec(),
        ]).comebacks,
        2,
      );
    });

    test('from wrong to right: a follow-up answered right after an answer '
        'that was not', () {
      final f = _facts([
        _rec(quality: AnswerQuality.wrong),
        _rec(followUp: true),
        _rec(),
        _rec(followUp: true),
        _rec(quality: AnswerQuality.partial),
        _rec(followUp: true, quality: AnswerQuality.wrong),
      ]);
      expect(f.wrongToRight, 1);
    });

    test('a hint in the same oefening, then right', () {
      final f = _facts([
        _rec(calls: {UsageCallKind.hint, UsageCallKind.grading}),
        _rec(calls: {UsageCallKind.hint}, quality: AnswerQuality.wrong),
        _rec(calls: {UsageCallKind.grading}),
      ]);
      expect(f.hintHits, 1);
    });

    test('a question of the student\'s own rides on a record\'s usage', () {
      final f = _facts([
        _rec(calls: {UsageCallKind.dialogue}),
        _rec(followUp: true, calls: {UsageCallKind.dialogue}),
        _rec(),
      ]);
      expect(f.ownQuestions, 2);
    });

    test('a disputed answer key, on any graded record', () {
      expect(_facts([_rec(disputed: true), _rec()]).keyDisputes, 1);
    });

    test('Rome: right more than five minutes after the question went up', () {
      final asked = DateTime(2026, 9, 14, 10);
      final f = _facts([
        _rec(at: asked.add(const Duration(minutes: 6)), askedAt: asked),
        _rec(at: asked.add(const Duration(minutes: 4)), askedAt: asked),
        _rec(
          at: asked.add(const Duration(minutes: 9)),
          askedAt: asked,
          quality: AnswerQuality.wrong,
        ),
        // A record from before the field: unknown, not counted.
        _rec(at: asked.add(const Duration(minutes: 30))),
      ]);
      expect(f.slowCorrect, 1);
    });
  });

  group('mastery', () {
    test(
      'LOs mastered once each; a stuck one mastered later is persevered',
      () {
        final f = _facts([
          _rec(status: [_status('lo1', stuck: true), _status('lo2')]),
          _rec(status: [_status('lo1', mastered: true), _status('lo2')]),
          _rec(
            status: [
              _status('lo1', mastered: true),
              _status('lo2', mastered: true),
            ],
          ),
          // Stuck after mastery is not persevering.
          _rec(status: [_status('lo2', stuck: true)]),
        ]);
        expect(f.masteredLos, 2);
        expect(f.persevered, 1);
      },
    );

    test('a warm-up\'s statuses are about the active subgoal', () {
      final f = _facts([
        _rec(
          subgoal: 's0',
          active: 's1',
          warmUp: true,
          status: [_status('lo1', mastered: true)],
        ),
        _rec(subgoal: 's1', status: [_status('lo1', mastered: true)]),
      ]);
      expect(f.masteredLos, 1, reason: 's1/lo1 both times');
    });

    test('the toughest LO: oefeningen that asked it up to its mastery', () {
      final f = _facts([
        _rec(los: ['lo1'], quality: AnswerQuality.wrong),
        _rec(los: ['lo1'], followUp: true),
        _rec(los: ['lo2'], status: [_status('lo2', mastered: true)]),
        _rec(los: ['lo1'], quality: AnswerQuality.wrong),
        _rec(los: ['lo1'], status: [_status('lo1', mastered: true)]),
        _rec(los: ['lo1']),
        // An LO asked many times but never mastered does not count.
        for (var i = 0; i < 9; i++) _rec(los: ['lo3']),
      ]);
      expect(f.toughest, 3);
    });

    test('milestones: subgoals moved past, once each, the active one of a '
        'warm-up', () {
      final f = _facts([
        _rec(advanced: true),
        _rec(advanced: true),
        _rec(subgoal: 's0', active: 's2', warmUp: true, advanced: true),
      ]);
      expect(f.milestones, 2);
    });

    test('Ctrl+Z: an ordinary oefening on a subgoal moved past before — not '
        'a warm-up, not a recheck, not the advancing answer itself', () {
      final f = _facts([
        _rec(subgoal: 's1', advanced: true),
        _rec(subgoal: 's2'),
        _rec(subgoal: 's1', warmUp: true, active: 's2'),
        _rec(subgoal: 's1', recheck: true, active: 's2'),
        _rec(subgoal: 's1'),
      ]);
      expect(f.backToFinished, 1);
    });

    test('"Kenner van …": the non-optional LOs of the non-optional subgoals '
        'of each hoofddoel', () {
      LearningObjective lo(String id, {bool optional = false}) =>
          LearningObjective(
            id: id,
            statement: id,
            kind: LoKind.apply,
            optional: optional,
          );
      final goals = [
        Goal(id: 'r1', title: 'Basis', order: 0),
        Goal(
          id: 's1',
          title: 'Print',
          parentId: 'r1',
          order: 1,
          objectives: [lo('lo1'), lo('lo-extra', optional: true)],
        ),
        Goal(
          id: 's2',
          title: 'Extra',
          parentId: 'r1',
          order: 2,
          optional: true,
          objectives: [lo('lo3')],
        ),
        Goal(
          id: 's3',
          title: 'Variabelen',
          parentId: 'r1',
          order: 3,
          objectives: [lo('lo4')],
        ),
        Goal(id: 'r2', title: 'Leeg', order: 1),
      ];
      final records = [
        _rec(subgoal: 's1', status: [_status('lo1', mastered: true)]),
      ];
      expect(_facts(records).experts, isNull, reason: 'goals not known');

      var f = _facts(records, goals: goals);
      expect(f.experts!['r1'], (mastered: 1, total: 2));
      expect(
        f.experts!.containsKey('r2'),
        isFalse,
        reason: 'nothing to master',
      );

      f = _facts([
        ...records,
        _rec(
          subgoal: 's3',
          los: ['lo4'],
          status: [_status('lo4', mastered: true)],
        ),
      ], goals: goals);
      expect(f.experts!['r1'], (mastered: 2, total: 2));
    });
  });

  group('moments, in local time', () {
    test('early bird, night owl, weekend, Friday afternoon, pi, Halloween', () {
      final f = _facts([
        _rec(at: DateTime(2026, 9, 14, 7, 59)),
        _rec(at: DateTime(2026, 9, 14, 8, 0)),
        _rec(at: DateTime(2026, 9, 14, 22, 0)),
        _rec(at: DateTime(2026, 9, 15, 2, 30)),
        _rec(at: DateTime(2026, 9, 19, 14)), // Saturday
        _rec(at: DateTime(2026, 9, 20, 14)), // Sunday
        _rec(at: DateTime(2026, 9, 18, 15, 30)), // Friday, right
        _rec(at: DateTime(2026, 9, 18, 16), quality: AnswerQuality.wrong),
        _rec(at: DateTime(2026, 9, 18, 14, 59)),
        _rec(at: DateTime(2026, 9, 16, 15, 14, 40)),
        _rec(at: DateTime(2027, 3, 14, 11)), // a Sunday
        _rec(at: DateTime(2026, 10, 31, 11)), // a Saturday
      ]);
      expect(f.earlyBird, 1);
      expect(f.nightOwl, 2);
      expect(f.weekend, 4);
      expect(f.fridayAfternoonCorrect, 1);
      expect(f.piMinute, 1);
      expect(f.piDay, 1);
      expect(f.halloween, 1);
    });

    test('a follow-up is no oefening for the moments either', () {
      final f = _facts([_rec(at: DateTime(2026, 9, 19, 14), followUp: true)]);
      expect(f.weekend, 0);
    });
  });
}
