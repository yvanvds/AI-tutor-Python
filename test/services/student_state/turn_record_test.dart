// Round trip of the `turn_history` doc fields added by #100.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

PersistedTurnRecord _record({
  EvidenceProvenance? provenance,
  List<TurnTransferCredit> transferCredits = const [],
  bool isWarmUp = false,
}) => PersistedTurnRecord(
  isWarmUp: isWarmUp,
  id: 't1',
  turnAt: DateTime.utc(2026, 9, 2, 10),
  subgoalId: 's1',
  targetLOIds: const ['lo1'],
  questionType: 'completeCodeQuestion',
  difficulty: QuestionDifficulty.medium,
  isFollowUp: false,
  chainDepth: 0,
  selectionReason: null,
  overallQuality: AnswerQuality.correct,
  loSignals: const [],
  hadFallback: false,
  appliedSignals: const [],
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  subgoalProgressAfter: 0.0,
  loStatusAfter: const [],
  subgoalAdvanced: false,
  provenance: provenance ?? EvidenceProvenance.home,
  transferCredits: transferCredits,
);

void main() {
  group('PersistedTurnRecord isWarmUp (#102)', () {
    test('an ordinary turn writes no field and reads back false', () {
      final map = _record().toMap(uid: 'u1');
      expect(map.containsKey('isWarmUp'), isFalse);
      expect(PersistedTurnRecord.fromCosmos(map).isWarmUp, isFalse);
    });

    test('a warm-up turn writes the flag and reads it back', () {
      final map = _record(isWarmUp: true).toMap(uid: 'u1');
      expect(map['isWarmUp'], isTrue);
      expect(PersistedTurnRecord.fromCosmos(map).isWarmUp, isTrue);
    });
  });

  group('PersistedTurnRecord transferCredits (#101)', () {
    test('an ordinary turn writes no field at all', () {
      expect(
        _record().toMap(uid: 'u1').containsKey('transferCredits'),
        isFalse,
      );
    });

    test('credits are written with their subgoal, LO and delta', () {
      final map = _record(
        transferCredits: const [
          TurnTransferCredit(
            subgoalId: 's0',
            loId: 'lo-print',
            alphaDelta: 0.5,
          ),
        ],
      ).toMap(uid: 'u1');
      expect(map['transferCredits'], [
        {'subgoalId': 's0', 'loId': 'lo-print', 'alphaDelta': 0.5},
      ]);
    });
  });

  group('PersistedTurnRecord provenance (#100)', () {
    test('defaults to home', () {
      expect(_record().provenance, EvidenceProvenance.home);
    });

    test('is written by name and read back', () {
      final map = _record(provenance: EvidenceProvenance.supervised)
          .toMap(uid: 'u1');
      expect(map['provenance'], 'supervised');
      expect(
        PersistedTurnRecord.fromCosmos(map).provenance,
        EvidenceProvenance.supervised,
      );
    });

    test('a doc written before the field existed reads as home', () {
      final map = _record().toMap(uid: 'u1')..remove('provenance');
      expect(
        PersistedTurnRecord.fromCosmos(map).provenance,
        EvidenceProvenance.home,
      );
    });

    test('an unknown value reads as home, never as supervised', () {
      final map = _record().toMap(uid: 'u1')..['provenance'] = 'anchor?';
      expect(
        PersistedTurnRecord.fromCosmos(map).provenance,
        EvidenceProvenance.home,
      );
    });
  });

  group('EvidenceProvenance.parse', () {
    test('round-trips every value', () {
      for (final p in EvidenceProvenance.values) {
        expect(EvidenceProvenance.parse(p.name), p);
      }
    });

    test('null and non-strings are home', () {
      expect(EvidenceProvenance.parse(null), EvidenceProvenance.home);
      expect(EvidenceProvenance.parse(1), EvidenceProvenance.home);
    });
  });
}
