// Round trip of the `turn_history` doc fields added by #100.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

PersistedTurnRecord _record({EvidenceProvenance? provenance}) =>
    PersistedTurnRecord(
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
    );

void main() {
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
