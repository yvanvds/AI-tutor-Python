// Issue #103 — the three-level difficulty ratchet on a belief doc.
//
// What matters at this layer is the wire format: the level round-trips by
// name, and a doc written before the field existed reads as *no level* and
// writes none back (#164) — the old-data reading of PUNTENFORMULE §2.5
// ("ever demonstrated at non-easy" → medium) is the grade formula's, at
// grade time, never the model's on disk.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _doc({
  Object? highest,
  bool includeHighest = false,
  String? lastPositiveAtCalibratedAt,
}) => {
  'id': 'u_s_lo',
  'type': 'lo_belief',
  'uid': 'u',
  'subgoalId': 's',
  'loId': 'lo',
  'alpha': 3.0,
  'beta': 1.0,
  'lastUpdatedAt': '2026-05-01T10:00:00Z',
  if (lastPositiveAtCalibratedAt != null)
    'lastPositiveAtCalibratedAt': lastPositiveAtCalibratedAt,
  if (includeHighest) 'highestPositiveDifficulty': highest,
};

void main() {
  group('LoBelief.highestPositiveDifficulty (#103)', () {
    test('is written by name and read back', () {
      for (final level in QuestionDifficulty.values) {
        final belief = LoBelief(
          subgoalId: 's',
          loId: 'lo',
          alpha: 3,
          beta: 1,
          lastUpdatedAt: DateTime.utc(2026, 5, 1),
          highestPositiveDifficulty: level,
        );
        final map = belief.toMap(uid: 'u');
        expect(map['highestPositiveDifficulty'], level.name);
        expect(LoBelief.fromCosmos(map).highestPositiveDifficulty, level);
      }
    });

    test('is omitted from the doc while there is no positive on record', () {
      final belief = LoBelief(
        subgoalId: 's',
        loId: 'lo',
        alpha: 1,
        beta: 1,
        lastUpdatedAt: DateTime.utc(2026, 5, 1),
      );
      expect(
        belief.toMap(uid: 'u').containsKey('highestPositiveDifficulty'),
        isFalse,
      );
    });

    test('a doc written before the field existed, with the old ratchet '
        'set, reads as no level and writes none back (#164)', () {
      // Before #164 this read as `medium` — a guess — and the next write
      // stored the guess as if it had been measured, permanently capping a
      // student who had really demonstrated the LO at hard.
      final b = LoBelief.fromCosmos(
        _doc(lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z'),
      );
      expect(b.lastPositiveAtCalibratedAt, isNotNull);
      expect(b.highestPositiveDifficulty, isNull);
      expect(
        b.toMap(uid: 'u').containsKey('highestPositiveDifficulty'),
        isFalse,
        reason: 'a level the app never measured must not reach the doc',
      );
    });

    test('a doc written before the field existed, without the old ratchet, '
        'reads as no level', () {
      final b = LoBelief.fromCosmos(_doc());
      expect(b.lastPositiveAtCalibratedAt, isNull);
      expect(b.highestPositiveDifficulty, isNull);
    });

    test('an explicit level wins over the old ratchet', () {
      // Hard with the timestamp: the level is authoritative.
      expect(
        LoBelief.fromCosmos(
          _doc(
            includeHighest: true,
            highest: 'hard',
            lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z',
          ),
        ).highestPositiveDifficulty,
        QuestionDifficulty.hard,
      );
      // Easy with the timestamp: a positive at easy while calibrated at
      // easy set the old flag; the level says what actually happened.
      expect(
        LoBelief.fromCosmos(
          _doc(
            includeHighest: true,
            highest: 'easy',
            lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z',
          ),
        ).highestPositiveDifficulty,
        QuestionDifficulty.easy,
      );
    });

    test('an unrecognised level is treated like a missing one', () {
      expect(
        LoBelief.fromCosmos(_doc(includeHighest: true, highest: 'impossible'))
            .highestPositiveDifficulty,
        isNull,
      );
      // ... which, with the old ratchet set, is still no level (#164).
      expect(
        LoBelief.fromCosmos(
          _doc(
            includeHighest: true,
            highest: 42,
            lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z',
          ),
        ).highestPositiveDifficulty,
        isNull,
      );
    });

    test('copyWith keeps the level unless given a new one', () {
      final b = LoBelief(
        subgoalId: 's',
        loId: 'lo',
        alpha: 3,
        beta: 1,
        lastUpdatedAt: DateTime.utc(2026, 5, 1),
        highestPositiveDifficulty: QuestionDifficulty.hard,
      );
      expect(
        b.copyWith(alpha: 4).highestPositiveDifficulty,
        QuestionDifficulty.hard,
      );
      expect(
        b
            .copyWith(highestPositiveDifficulty: QuestionDifficulty.easy)
            .highestPositiveDifficulty,
        QuestionDifficulty.easy,
      );
    });
  });

  group('LoBelief.firstMasteredAt (#101)', () {
    final stamp = DateTime.utc(2026, 6, 15, 9, 30);

    test('is written as ISO 8601 and read back', () {
      final belief = LoBelief(
        subgoalId: 's',
        loId: 'lo',
        alpha: 5,
        beta: 1,
        lastUpdatedAt: DateTime.utc(2026, 5, 1),
        firstMasteredAt: stamp,
      );
      final map = belief.toMap(uid: 'u');
      expect(map['firstMasteredAt'], stamp.toIso8601String());
      expect(LoBelief.fromCosmos(map).firstMasteredAt, stamp);
    });

    test('is omitted from the doc until the LO has mastered', () {
      final belief = LoBelief(
        subgoalId: 's',
        loId: 'lo',
        alpha: 1,
        beta: 1,
        lastUpdatedAt: DateTime.utc(2026, 5, 1),
      );
      expect(belief.toMap(uid: 'u').containsKey('firstMasteredAt'), isFalse);
      expect(LoBelief.fromCosmos(_doc()).firstMasteredAt, isNull);
    });

    test('a malformed value reads as absent', () {
      expect(
        LoBelief.fromCosmos({..._doc(), 'firstMasteredAt': 42}).firstMasteredAt,
        isNull,
      );
    });

    test('copyWith keeps the stamp unless given one', () {
      final b = LoBelief(
        subgoalId: 's',
        loId: 'lo',
        alpha: 5,
        beta: 1,
        lastUpdatedAt: DateTime.utc(2026, 5, 1),
        firstMasteredAt: stamp,
      );
      expect(b.copyWith(alpha: 4).firstMasteredAt, stamp);
      final later = DateTime.utc(2026, 7, 1);
      expect(b.copyWith(firstMasteredAt: later).firstMasteredAt, later);
    });
  });

  group('LoBelief.regressedAt (#112)', () {
    final flag = DateTime.utc(2026, 9, 3, 11, 15);

    LoBelief belief({DateTime? regressedAt}) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 5,
      beta: 2,
      lastUpdatedAt: DateTime.utc(2026, 9, 3),
      firstMasteredAt: DateTime.utc(2026, 6, 15),
      regressedAt: regressedAt,
    );

    test('is written as ISO 8601 and read back', () {
      final map = belief(regressedAt: flag).toMap(uid: 'u');
      expect(map['regressedAt'], flag.toIso8601String());
      expect(LoBelief.fromCosmos(map).regressedAt, flag);
    });

    test('is omitted from the doc while the LO is not regressed, and a '
        'doc written before the field existed reads as not regressed', () {
      expect(belief().toMap(uid: 'u').containsKey('regressedAt'), isFalse);
      expect(LoBelief.fromCosmos(_doc()).regressedAt, isNull);
    });

    test('a malformed value reads as absent', () {
      expect(
        LoBelief.fromCosmos({..._doc(), 'regressedAt': 42}).regressedAt,
        isNull,
      );
    });

    test('copyWith keeps the flag, sets it, or clears it explicitly', () {
      final b = belief(regressedAt: flag);
      expect(b.copyWith(alpha: 4).regressedAt, flag);
      final later = DateTime.utc(2026, 9, 4);
      expect(b.copyWith(regressedAt: later).regressedAt, later);
      expect(b.copyWith(clearRegressedAt: true).regressedAt, isNull);
      expect(belief().copyWith(alpha: 4).regressedAt, isNull);
    });
  });

  group('LoBelief.lastProbedAt (#187)', () {
    final probed = DateTime.utc(2026, 9, 11, 8, 53);
    final updated = DateTime.utc(2026, 9, 18, 9, 30);

    LoBelief belief({DateTime? lastProbedAt, String? lastQuestionType}) =>
        LoBelief(
          subgoalId: 's',
          loId: 'lo',
          alpha: 6,
          beta: 2,
          lastUpdatedAt: updated,
          lastQuestionType: lastQuestionType,
          lastProbedAt: lastProbedAt,
        );

    test('is written as ISO 8601 and read back', () {
      final map = belief(lastProbedAt: probed).toMap(uid: 'u');
      expect(map['lastProbedAt'], probed.toIso8601String());
      expect(LoBelief.fromCosmos(map).lastProbedAt, probed);
    });

    test('is omitted while unknown; a malformed value reads as absent', () {
      expect(belief().toMap(uid: 'u').containsKey('lastProbedAt'), isFalse);
      expect(LoBelief.fromCosmos(_doc()).lastProbedAt, isNull);
      expect(
        LoBelief.fromCosmos({..._doc(), 'lastProbedAt': 42}).lastProbedAt,
        isNull,
      );
    });

    test('copyWith keeps it unless given one', () {
      final b = belief(lastProbedAt: probed);
      expect(b.copyWith(alpha: 7, lastUpdatedAt: updated).lastProbedAt, probed);
      expect(b.copyWith(lastProbedAt: updated).lastProbedAt, updated);
    });

    test('lastDirectProbeAt is the field when set, even if the doc was '
        'written since — a later write from the side is not a probe', () {
      expect(
        belief(
          lastProbedAt: probed,
          lastQuestionType: 'mcQuestion',
        ).lastDirectProbeAt,
        probed,
      );
    });

    test('on a doc from before the field, lastDirectProbeAt falls back to '
        'lastUpdatedAt when the LO was ever the target of a question, and '
        'is null for an LO never asked directly', () {
      expect(
        belief(lastQuestionType: 'mcQuestion').lastDirectProbeAt,
        updated,
        reason: 'never earlier than the real last probe: due late, not early',
      );
      expect(belief().lastDirectProbeAt, isNull);
    });
  });

  group('LoBelief.ownQuestions (#278)', () {
    LoBelief belief({int ownQuestions = 0}) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 2.4,
      beta: 5,
      lastUpdatedAt: DateTime.utc(2026, 11, 9),
      ownQuestions: ownQuestions,
    );

    test('is written and read back', () {
      final map = belief(ownQuestions: 6).toMap(uid: 'u');
      expect(map['ownQuestions'], 6);
      expect(LoBelief.fromCosmos(map).ownQuestions, 6);
    });

    test('a doc from before formula 1.1 reads 0, so its LO is stuck only '
        'after six new own questions; a malformed value reads 0 too', () {
      expect(LoBelief.fromCosmos(_doc()).ownQuestions, 0);
      expect(
        LoBelief.fromCosmos({..._doc(), 'ownQuestions': 'six'}).ownQuestions,
        0,
      );
      expect(
        LoBelief.fromCosmos({..._doc(), 'ownQuestions': 7.0}).ownQuestions,
        7,
      );
    });

    test('copyWith keeps it unless given one', () {
      final b = belief(ownQuestions: 3);
      expect(b.copyWith(alpha: 3).ownQuestions, 3);
      expect(b.copyWith(ownQuestions: 4).ownQuestions, 4);
    });
  });

  group('LoBelief.ownQuestionsRight and ownQuestionsRightNonMcq (#279)', () {
    LoBelief belief({int? right, int? nonMcq}) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 5,
      beta: 1,
      lastUpdatedAt: DateTime.utc(2026, 11, 9),
      ownQuestions: 3,
      ownQuestionsRight: right,
      ownQuestionsRightNonMcq: nonMcq,
    );

    test('are written and read back, 0 as 0', () {
      final map = belief(right: 2, nonMcq: 0).toMap(uid: 'u');
      expect(map['ownQuestionsRight'], 2);
      expect(map['ownQuestionsRightNonMcq'], 0);
      final back = LoBelief.fromCosmos(map);
      expect(back.ownQuestionsRight, 2);
      expect(back.ownQuestionsRightNonMcq, 0);
      expect(back.hasRightCounts, isTrue);
    });

    test('missing stays missing — not 0 — in the model and on disk: #275 '
        'tells a stamp from before 1.1 from a thin one by it', () {
      final old = LoBelief.fromCosmos(_doc());
      expect(old.ownQuestionsRight, isNull);
      expect(old.ownQuestionsRightNonMcq, isNull);
      expect(old.hasRightCounts, isFalse);
      final map = old.toMap(uid: 'u');
      expect(map.containsKey('ownQuestionsRight'), isFalse);
      expect(map.containsKey('ownQuestionsRightNonMcq'), isFalse);
      // A malformed value is a missing one.
      expect(
        LoBelief.fromCosmos({..._doc(), 'ownQuestionsRight': 'two'})
            .ownQuestionsRight,
        isNull,
      );
      expect(
        LoBelief.fromCosmos({..._doc(), 'ownQuestionsRightNonMcq': 1.0})
            .ownQuestionsRightNonMcq,
        1,
      );
    });

    test('copyWith keeps them unless given', () {
      final b = belief(right: 2, nonMcq: 1);
      expect(b.copyWith(alpha: 3).ownQuestionsRight, 2);
      expect(b.copyWith(alpha: 3).ownQuestionsRightNonMcq, 1);
      expect(b.copyWith(ownQuestionsRight: 3).ownQuestionsRight, 3);
      expect(belief().copyWith(alpha: 3).hasRightCounts, isFalse);
    });
  });

  group('LoBelief.returnWrongAt and thinCheckedAt (#275)', () {
    LoBelief belief({DateTime? wrong, DateTime? checked}) => LoBelief(
      subgoalId: 's',
      loId: 'lo',
      alpha: 3,
      beta: 2,
      lastUpdatedAt: DateTime.utc(2026, 11, 9),
      returnWrongAt: wrong,
      thinCheckedAt: checked,
    );

    test('are written and read back; missing on an older doc', () {
      final at = DateTime.utc(2026, 11, 9, 10);
      final map = belief(wrong: at, checked: at).toMap(uid: 'u');
      expect(map['returnWrongAt'], '2026-11-09T10:00:00.000Z');
      expect(map['thinCheckedAt'], '2026-11-09T10:00:00.000Z');
      final back = LoBelief.fromCosmos(map);
      expect(back.returnWrongAt, at);
      expect(back.thinCheckedAt, at);

      final old = LoBelief.fromCosmos(_doc());
      expect(old.returnWrongAt, isNull);
      expect(old.thinCheckedAt, isNull);
      final oldMap = old.toMap(uid: 'u');
      expect(oldMap.containsKey('returnWrongAt'), isFalse);
      expect(oldMap.containsKey('thinCheckedAt'), isFalse);
      expect(
        LoBelief.fromCosmos({..._doc(), 'returnWrongAt': 12}).returnWrongAt,
        isNull,
      );
    });

    test('copyWith keeps them unless given; returnWrongAt clears only on '
        'request', () {
      final at = DateTime.utc(2026, 11, 9, 10);
      final b = belief(wrong: at, checked: at);
      expect(b.copyWith(alpha: 4).returnWrongAt, at);
      expect(b.copyWith(alpha: 4).thinCheckedAt, at);
      expect(b.copyWith(clearReturnWrongAt: true).returnWrongAt, isNull);
      expect(b.copyWith(clearReturnWrongAt: true).thinCheckedAt, at);
    });
  });
}
