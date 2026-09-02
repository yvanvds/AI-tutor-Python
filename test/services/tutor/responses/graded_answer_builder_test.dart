// `GradedAnswerBuilder` carries the turn's provenance (#100) into the
// `GradedAnswer` on every branch — accepted signals, the synthesised
// fallback, and the no-target fallback — so the conductor never sees a
// turn without it.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/responses/graded_answer_builder.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:flutter_test/flutter_test.dart';

const _lo = LearningObjective(id: 'lo1', statement: 'one', kind: LoKind.apply);
final _scope = [
  Goal(id: 's1', title: 's', parentId: 'r', order: 0, objectives: const [_lo]),
];
const _inScope = LoSignal(
  subgoalId: 's1',
  loId: 'lo1',
  kind: LoSignalKind.positive,
  strength: LoSignalStrength.strong,
);
const _outOfScope = LoSignal(
  subgoalId: 'elsewhere',
  loId: 'lo1',
  kind: LoSignalKind.positive,
  strength: LoSignalStrength.strong,
);

void main() {
  test('defaults to home', () {
    final a = GradedAnswerBuilder.build(
      overallQuality: AnswerQuality.correct,
      rawSignals: const [_inScope],
      scopeSubgoals: _scope,
      intendedTargetLO: _lo,
      intendedTargetSubgoalId: 's1',
    );
    expect(a.provenance, EvidenceProvenance.home);
    expect(a.hadFallback, isFalse);
  });

  test('accepted signals keep the provenance', () {
    final a = GradedAnswerBuilder.build(
      overallQuality: AnswerQuality.correct,
      rawSignals: const [_inScope],
      scopeSubgoals: _scope,
      intendedTargetLO: _lo,
      intendedTargetSubgoalId: 's1',
      provenance: EvidenceProvenance.supervised,
    );
    expect(a.hadFallback, isFalse);
    expect(a.provenance, EvidenceProvenance.supervised);
  });

  test('the synthesised fallback signal keeps the provenance', () {
    final a = GradedAnswerBuilder.build(
      overallQuality: AnswerQuality.correct,
      rawSignals: const [_outOfScope],
      scopeSubgoals: _scope,
      intendedTargetLO: _lo,
      intendedTargetSubgoalId: 's1',
      provenance: EvidenceProvenance.supervised,
    );
    expect(a.hadFallback, isTrue);
    expect(a.signals, hasLength(1));
    expect(a.provenance, EvidenceProvenance.supervised);
  });

  group('transferLOs (#101)', () {
    const earlier = LearningObjective(
      id: 'lo-print',
      statement: 'print',
      kind: LoKind.apply,
    );
    final scope = [
      Goal(
        id: 's0',
        title: 'Print',
        parentId: 'r',
        order: 0,
        objectives: const [earlier],
      ),
      ..._scope,
    ];

    test('in-scope refs are kept, out-of-scope ones dropped, duplicates '
        'collapsed', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [_inScope],
        rawTransferLOs: const [
          TransferLoRef(subgoalId: 's0', loId: 'lo-print'),
          TransferLoRef(subgoalId: 's0', loId: 'lo-print'),
          TransferLoRef(subgoalId: 's0', loId: 'lo-nope'),
          TransferLoRef(subgoalId: 'elsewhere', loId: 'lo-print'),
        ],
        scopeSubgoals: scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.hadFallback, isFalse);
      expect(a.transferLOs, hasLength(1));
      expect(a.transferLOs.single.subgoalId, 's0');
      expect(a.transferLOs.single.loId, 'lo-print');
    });

    test('a valid ref does not rescue a turn whose signals all dropped', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [_outOfScope],
        rawTransferLOs: const [
          TransferLoRef(subgoalId: 's0', loId: 'lo-print'),
        ],
        scopeSubgoals: scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.hadFallback, isTrue);
      expect(a.signals.single.loId, 'lo1');
      // Carried along; the conductor declines it on a fallback turn.
      expect(a.transferLOs, hasLength(1));
    });

    test('defaults to none', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [_inScope],
        scopeSubgoals: scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.transferLOs, isEmpty);
    });
  });

  test('the no-target fallback keeps the provenance', () {
    final a = GradedAnswerBuilder.build(
      overallQuality: AnswerQuality.correct,
      rawSignals: const [_outOfScope],
      scopeSubgoals: _scope,
      intendedTargetLO: null,
      intendedTargetSubgoalId: null,
      provenance: EvidenceProvenance.supervised,
    );
    expect(a.hadFallback, isTrue);
    expect(a.signals, isEmpty);
    expect(a.provenance, EvidenceProvenance.supervised);
  });
}
