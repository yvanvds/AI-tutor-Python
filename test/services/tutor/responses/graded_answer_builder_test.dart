// `GradedAnswerBuilder` carries the turn's provenance (#100) into the
// `GradedAnswer` on every branch — accepted signals, the synthesised
// fallback, and the no-target fallback — so the conductor never sees a
// turn without it.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
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

  group('a signal on the asked LO outside the scope (#225)', () {
    // The student is on the first subgoal of a new root ("cond"), while the
    // scope is still the old root's subgoals: the grader's signal on the
    // asked LO is dropped, and its side signal on the old root is not.
    const asked = LearningObjective(
      id: 'lo-cmp',
      statement: 'compare',
      kind: LoKind.apply,
    );
    const onAsked = LoSignal(
      subgoalId: 'cond',
      loId: 'lo-cmp',
      kind: LoSignalKind.positive,
      strength: LoSignalStrength.strong,
    );
    const onOldRoot = LoSignal(
      subgoalId: 's1',
      loId: 'lo1',
      kind: LoSignalKind.positive,
      strength: LoSignalStrength.weak,
    );

    test('is handed on as lost, and no fallback stands in for it', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [onAsked, onOldRoot],
        scopeSubgoals: _scope,
        intendedTargetLO: asked,
        intendedTargetSubgoalId: 'cond',
      );
      expect(a.hadFallback, isFalse);
      expect(a.signals.map((s) => '${s.subgoalId}/${s.loId}'), ['s1/lo1']);
      final lost = a.lostTargetSignals.single;
      expect(lost.subgoalId, 'cond');
      expect(lost.loId, 'lo-cmp');
      expect(lost.kind, LoSignalKind.positive);
      expect(lost.strength, LoSignalStrength.strong);
    });

    test('is handed on as lost when the fallback does stand in', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [onAsked],
        scopeSubgoals: _scope,
        intendedTargetLO: asked,
        intendedTargetSubgoalId: 'cond',
      );
      expect(a.hadFallback, isTrue);
      expect(a.signals.single.loId, 'lo-cmp');
      expect(a.signals.single.strength, LoSignalStrength.weak);
      expect(a.lostTargetSignals.single.strength, LoSignalStrength.strong);
    });

    test('in scope, it is no loss', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [onAsked],
        scopeSubgoals: [
          ..._scope,
          Goal(
            id: 'cond',
            title: 'c',
            parentId: 'r',
            order: 1,
            objectives: const [asked],
          ),
        ],
        intendedTargetLO: asked,
        intendedTargetSubgoalId: 'cond',
      );
      expect(a.signals.single.loId, 'lo-cmp');
      expect(a.lostTargetSignals, isEmpty);
    });

    test('a dropped signal on another LO is no loss of the target', () {
      // `_outOfScope` names lo1 under a subgoal outside the scope: dropped,
      // but the question asked about lo1 in s1.
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [_inScope, _outOfScope],
        scopeSubgoals: _scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.lostTargetSignals, isEmpty);
    });

    test('an LO removed from a subgoal in scope is a curriculum edit, not a '
        'loss', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [
          LoSignal(
            subgoalId: 's1',
            loId: 'lo-gone',
            kind: LoSignalKind.positive,
            strength: LoSignalStrength.strong,
          ),
        ],
        scopeSubgoals: _scope,
        intendedTargetLO: const LearningObjective(
          id: 'lo-gone',
          statement: 'gone',
          kind: LoKind.apply,
        ),
        intendedTargetSubgoalId: 's1',
      );
      expect(a.lostTargetSignals, isEmpty);
    });
  });

  group('#228: every signal the scope check drops is handed on with why', () {
    const asked = LearningObjective(
      id: 'lo-cmp',
      statement: 'compare',
      kind: LoKind.apply,
    );
    String row(DroppedSignal d) =>
        '${d.signal.subgoalId}/${d.signal.loId} '
        '${d.signal.kind.name}/${d.signal.strength.name} ${d.reason.name}';

    test('out of scope, the asked LO out of scope, and an LO its subgoal '
        'does not have — in the grader\'s order, none of them accepted', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.partial,
        rawSignals: const [
          LoSignal(
            subgoalId: 'cond',
            loId: 'lo-cmp',
            kind: LoSignalKind.neutral,
            strength: LoSignalStrength.moderate,
          ),
          _inScope,
          _outOfScope,
          LoSignal(
            subgoalId: 's1',
            loId: 'lo-gone',
            kind: LoSignalKind.negative,
            strength: LoSignalStrength.weak,
          ),
        ],
        scopeSubgoals: _scope,
        intendedTargetLO: asked,
        intendedTargetSubgoalId: 'cond',
      );
      expect(a.signals.map((s) => '${s.subgoalId}/${s.loId}'), ['s1/lo1']);
      expect(a.droppedSignals.map(row), [
        'cond/lo-cmp neutral/moderate targetOutOfScope',
        'elsewhere/lo1 positive/strong outOfScope',
        's1/lo-gone negative/weak unknownLo',
      ]);
      // The target's own loss is still handed on for the #225 event.
      expect(a.lostTargetSignals.single.loId, 'lo-cmp');
    });

    test('also when every signal drops and the fallback stands in', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.wrong,
        rawSignals: const [_outOfScope],
        scopeSubgoals: _scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.hadFallback, isTrue);
      expect(a.droppedSignals.map(row), [
        'elsewhere/lo1 positive/strong outOfScope',
      ]);
    });

    test('and without a target to fall back on', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.wrong,
        rawSignals: const [_outOfScope],
        scopeSubgoals: _scope,
        intendedTargetLO: null,
        intendedTargetSubgoalId: null,
      );
      expect(a.signals, isEmpty);
      expect(a.droppedSignals.map(row), [
        'elsewhere/lo1 positive/strong outOfScope',
      ]);
    });

    test('nothing dropped, nothing listed', () {
      final a = GradedAnswerBuilder.build(
        overallQuality: AnswerQuality.correct,
        rawSignals: const [_inScope],
        scopeSubgoals: _scope,
        intendedTargetLO: _lo,
        intendedTargetSubgoalId: 's1',
      );
      expect(a.droppedSignals, isEmpty);
    });
  });
}
