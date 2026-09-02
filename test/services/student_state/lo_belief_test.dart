// Issue #103 — the three-level difficulty ratchet on a belief doc.
//
// What matters at this layer is the wire format: the level round-trips by
// name, and a doc written before the field existed reads the way the old
// binary ratchet was documented ("ever demonstrated at non-easy" → medium).

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
        'set, reads as medium', () {
      final b = LoBelief.fromCosmos(
        _doc(lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z'),
      );
      expect(b.lastPositiveAtCalibratedAt, isNotNull);
      expect(b.highestPositiveDifficulty, QuestionDifficulty.medium);
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
      expect(
        LoBelief.fromCosmos(
          _doc(
            includeHighest: true,
            highest: 42,
            lastPositiveAtCalibratedAt: '2026-05-01T10:00:00Z',
          ),
        ).highestPositiveDifficulty,
        QuestionDifficulty.medium,
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
}
