// #165: every `turn_history` doc says which build wrote it, so a laptop that
// has fallen behind — and whose `toMap`s therefore drop the fields newer
// builds added, on every write — shows in the audit trail instead of having
// to be inferred from the shape of the belief docs it leaves behind.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

PersistedTurnRecord _record({String? clientVersion}) => PersistedTurnRecord(
  id: 't1',
  turnAt: DateTime.utc(2026, 9, 23, 8, 33),
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
  clientVersion: clientVersion,
);

void main() {
  late InMemoryCosmos store;

  TurnHistoryService service({String? clientVersion}) => TurnHistoryService(
    container: store.container,
    getUid: () => 'u1',
    clientVersion: clientVersion,
  );

  setUp(() => store = InMemoryCosmos());

  test(
    'a graded turn is written with the version its record carries',
    () async {
      await service(clientVersion: '2.5.0+22')
          .append(_record(clientVersion: '2.5.0+22'));

      final doc = store.docs.values.single;
      expect(doc['clientVersion'], '2.5.0+22');
      expect(doc['uid'], 'u1');
    },
  );

  test("an audit stub carries the service's own version", () async {
    await service(clientVersion: '2.5.0+22').appendAudit(
      subgoalId: 's1',
      event: TurnSignalEvent.of(TurnSignalEventKind.emptyObjectivesBlock),
      at: DateTime.utc(2026, 9, 23, 8, 33),
    );

    final doc = store.docs.values.single;
    expect(doc['clientVersion'], '2.5.0+22');
    expect(doc['questionType'], '', reason: 'still the audit stub shape');
    expect((doc['signalEvents'] as List), hasLength(1));
  });

  test('with no version known, nothing is written for it', () async {
    await service().appendAudit(
      subgoalId: 's1',
      event: TurnSignalEvent.of(TurnSignalEventKind.emptyObjectivesBlock),
    );
    await service().append(_record());

    for (final doc in store.docs.values) {
      expect(doc.containsKey('clientVersion'), isFalse);
    }
  });

  test('listQuestionIdsFor names the bank questions the student answered on '
      'one subgoal (#186)', () async {
    Map<String, dynamic> doc(
      String id, {
      String uid = 'u1',
      String subgoalId = 's1',
      String? questionId,
    }) => {
      'id': id,
      'type': 'turn_history',
      'uid': uid,
      'subgoalId': subgoalId,
      'questionType': 'mcQuestion',
      'questionId': ?questionId,
    };
    store = InMemoryCosmos([
      doc('t1', questionId: 's1_a'),
      doc('t2', questionId: 's1_b'),
      doc('t3'),
      doc('t4', subgoalId: 's0', questionId: 's0_c'),
      doc('t5', uid: 'u2', questionId: 's1_d'),
    ]);

    expect(await service().listQuestionIdsFor('s1'), {'s1_a', 's1_b'});
    expect(await service().listQuestionIdsFor('s0'), {'s0_c'});
    expect(await service().listQuestionIdsFor('s9'), isEmpty);

    final signedOut = TurnHistoryService(
      container: store.container,
      getUid: () => null,
    );
    expect(await signedOut.listQuestionIdsFor('s1'), isEmpty);
  });
}
