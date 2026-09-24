// Issue #185 — the question bank service over an in-memory `questions`
// container: storing a question once however often it is asked, counting
// its answers, keeping the first feedback per option, the teacher's review
// actions, and the two error contracts — best-effort on the student's side
// (a missing container is logged, never thrown, and left alone for a while),
// throwing on the teacher's.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

BankQuestion _mcq({String subgoalId = 's1', DateTime? at}) =>
    BankQuestion.fromResponse(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: 'Wat drukt dit af?',
        code: 'print(1 + 1)',
        options: const ['2', '11', 'Error'],
        correct: '2',
      ),
      subgoalId: subgoalId,
      rootGoalId: 'r1',
      targetLOIds: const ['lo-print'],
      difficulty: QuestionDifficulty.medium,
      language: 'nl',
      model: 'gpt-5-mini',
      createdByUid: 'u1',
      createdAt: at ?? DateTime.utc(2026, 9, 24, 8),
    )!;

BankQuestion _code(String prompt, {String subgoalId = 's1', DateTime? at}) =>
    BankQuestion.fromResponse(
      CompleteCode(type: 'complete_code', prompt: prompt, code: 'x = ___'),
      subgoalId: subgoalId,
      rootGoalId: 'r1',
      targetLOIds: const ['lo-var'],
      difficulty: QuestionDifficulty.easy,
      language: 'nl',
      model: 'gpt-5-mini',
      createdByUid: 'u2',
      createdAt: at ?? DateTime.utc(2026, 9, 24, 9),
    )!;

/// A container whose reads — or, with [holdCreates], whose creates — wait
/// for [release] once [hold] is set: a bank that is slow to answer.
class _SlowContainer implements CosmosContainer {
  _SlowContainer(this._inner, {this.holdCreates = false});
  final CosmosContainer _inner;
  final bool holdCreates;

  bool hold = false;
  final Completer<void> _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) async {
    if (hold && !holdCreates) await _gate.future;
    return _inner.read(id, partitionKey: partitionKey);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) => _inner.query(
    sql,
    parameters: parameters,
    partitionKey: partitionKey,
    crossPartition: crossPartition,
  );

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    if (hold && holdCreates) await _gate.future;
    return _inner.create(doc, partitionKey: partitionKey);
  }

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => _inner.upsert(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) => _inner.replace(id, doc, partitionKey: partitionKey);

  @override
  Future<void> delete(String id, {required Object partitionKey}) =>
      _inner.delete(id, partitionKey: partitionKey);

  @override
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) => _inner.executeBatch(ops, partitionKey: partitionKey);
}

/// A container whose queries are answered by [answer] — one that hangs, or
/// one that fails — counting them; everything else goes to [_inner].
class _QueryContainer extends _SlowContainer {
  _QueryContainer(super.inner, this.answer);
  final Future<List<Map<String, dynamic>>> Function() answer;
  int queries = 0;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) {
    queries++;
    return answer();
  }
}

void main() {
  late InMemoryCosmos store;
  late DateTime now;
  late QuestionBankService bank;

  setUp(() {
    store = InMemoryCosmos();
    now = DateTime.utc(2026, 9, 24, 10);
    bank = QuestionBankService(container: store.container, now: () => now);
  });

  group('recordAsked', () {
    test('stores a new question once, and counts every further ask on the '
        'same doc', () async {
      final q = _mcq();
      await bank.recordAsked(q);

      expect(store.docs.keys, [q.id]);
      expect(store[q.id]!['askedCount'], 1);
      expect(store[q.id]!['lastAskedAt'], '2026-09-24T10:00:00.000Z');
      expect(store[q.id]!['type'], 'question');
      expect(store[q.id]!['subgoalId'], 's1');
      expect(store[q.id]!['status'], 'active');
      expect(store[q.id]!['payload']['correct'], '2');

      now = now.add(const Duration(hours: 1));
      // The same generation, asked of another student.
      await bank.recordAsked(_mcq(at: now));

      expect(store.docs, hasLength(1));
      expect(store[q.id]!['askedCount'], 2);
      expect(store[q.id]!['lastAskedAt'], '2026-09-24T11:00:00.000Z');
      // The first student's doc is the one that stays.
      expect(store[q.id]!['createdAt'], '2026-09-24T08:00:00.000Z');
    });

    test('a question another app stored in the meantime is counted, not '
        'overwritten', () async {
      final q = _mcq();
      final slow = _SlowContainer(store.container, holdCreates: true)
        ..hold = true;
      final racing = QuestionBankService(container: slow, now: () => now);
      final pending = racing.recordAsked(q);
      await Future<void>.delayed(Duration.zero);
      // This app found no doc and is about to create it; another student's
      // app stores the same generation first, so the create hits a 409.
      await bank.recordAsked(q);
      slow.release();
      await pending;

      expect(store.docs, hasLength(1));
      expect(store[q.id]!['askedCount'], 2);
    });

    test("a newer build's fields on the doc survive the write", () async {
      final q = _mcq();
      await bank.recordAsked(q);
      store.docs[q.id]!['futureField'] = 'keep me';

      await bank.recordAsked(q);
      expect(store[q.id]!['futureField'], 'keep me');
    });
  });

  group('recordAnswer', () {
    test('counts answers and correct answers, and keeps the first feedback '
        'per option with its verdict', () async {
      final q = _mcq();
      await bank.recordAsked(q);

      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        pickedOption: '11',
        feedback: 'Nee: 1 + 1 is een som, geen tekst.',
        quality: AnswerQuality.wrong,
      );
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: true,
        pickedOption: '2',
        feedback: 'Juist.',
        quality: AnswerQuality.correct,
      );
      // A later pick of the same option does not replace the text.
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        pickedOption: '11',
        feedback: 'Andere tekst.',
        quality: AnswerQuality.wrong,
      );

      final stored = BankQuestion.tryFromCosmos(store[q.id]!)!;
      expect(stored.askedCount, 1);
      expect(stored.answeredCount, 3);
      expect(stored.correctCount, 1);
      expect(stored.optionFeedback.map((f) => f.toJson()), [
        {
          'option': '11',
          'text': 'Nee: 1 + 1 is een som, geen tekst.',
          'quality': 'wrong',
        },
        {'option': '2', 'text': 'Juist.', 'quality': 'correct'},
      ]);
    });

    test('a pick that is not one of the options, or no feedback, stores no '
        'feedback but still counts', () async {
      final q = _mcq();
      await bank.recordAsked(q);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        pickedOption: 'typed in the chat',
        feedback: 'Nee.',
      );
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: true,
        pickedOption: '2',
        feedback: '  ',
      );

      final stored = BankQuestion.tryFromCosmos(store[q.id]!)!;
      expect(stored.answeredCount, 2);
      expect(stored.correctCount, 1);
      expect(stored.optionFeedback, isEmpty);
    });

    test(
      'an answer to a question the bank never stored is left alone',
      () async {
        await bank.recordAnswer(
          questionId: 's1_unknown',
          subgoalId: 's1',
          correct: true,
        );
        expect(store.docs, isEmpty);
      },
    );

    test('an answer never overtakes the write that stores its question, '
        'however slow the bank is', () async {
      final slow = _SlowContainer(store.container)..hold = true;
      final queued = QuestionBankService(container: slow, now: () => now);
      final q = _mcq();

      final asked = queued.recordAsked(q);
      final answered = queued.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.docs, isEmpty, reason: 'the bank has not answered yet');

      slow.release();
      await Future.wait([asked, answered]);
      expect(store[q.id]!['askedCount'], 1);
      expect(store[q.id]!['answeredCount'], 1);
      expect(store[q.id]!['correctCount'], 1);
    });
  });

  group('without a `questions` container', () {
    late UnprovisionedCosmos missing;

    setUp(() {
      missing = UnprovisionedCosmos('questions');
      bank = QuestionBankService(container: missing.container, now: () => now);
    });

    test('the tutor-side writes complete without throwing, and the bank is '
        'left alone for a while before it is tried again', () async {
      await expectLater(bank.recordAsked(_mcq()), completes);
      final afterFirst = missing.requests.length;
      expect(afterFirst, greaterThan(0));

      await expectLater(
        bank.recordAnswer(
          questionId: _mcq().id,
          subgoalId: 's1',
          correct: true,
        ),
        completes,
      );
      await bank.recordAsked(_code('Maak x vijf.'));
      expect(
        missing.requests.length,
        afterFirst,
        reason: 'within the back-off nothing is sent',
      );

      now = now.add(kQuestionBankRetryAfter);
      await bank.recordAsked(_mcq());
      expect(missing.requests.length, greaterThan(afterFirst));
      expect(missing.writes, isEmpty);
    });

    test(
      'the tutor-side read (#186) says "unknown" instead of throwing, and '
      'backs off like the writes: neither is tried again for a while',
      () async {
        expect(await bank.listServable('s1'), isNull);
        final afterFirst = missing.requests.length;
        expect(afterFirst, greaterThan(0));

        expect(await bank.listServable('s1'), isNull);
        await bank.recordAsked(_mcq());
        expect(missing.requests.length, afterFirst);

        now = now.add(kQuestionBankRetryAfter);
        expect(await bank.listServable('s1'), isNull);
        expect(missing.requests.length, greaterThan(afterFirst));
      },
    );

    test('the teacher-side reads throw a ContainerNotFound the page can '
        'name', () async {
      await expectLater(
        bank.listSummaries(),
        throwsA(
          isA<CosmosException>().having(
            (e) => e.isContainerNotFound,
            'isContainerNotFound',
            isTrue,
          ),
        ),
      );
      await expectLater(
        bank.listForSubgoal('s1'),
        throwsA(isA<CosmosException>()),
      );
    });
  });

  group('reads', () {
    test('listForSubgoal reads one subgoal, newest first, and can keep to the '
        'questions that may be served', () async {
      final older = _code('Maak x vijf.', at: DateTime.utc(2026, 9, 20));
      final newer = _code('Maak x tien.', at: DateTime.utc(2026, 9, 22));
      final elsewhere = _mcq(subgoalId: 's2');
      for (final q in [older, newer, elsewhere]) {
        await bank.recordAsked(q);
      }
      await bank.setHidden(newer, true);

      expect((await bank.listForSubgoal('s1')).map((q) => q.id), [
        newer.id,
        older.id,
      ]);
      expect(
        (await bank.listForSubgoal('s1', activeOnly: true)).map((q) => q.id),
        [older.id],
      );
      expect(
        (await bank.get(elsewhere.id, subgoalId: 's2'))!.questionType,
        elsewhere.questionType,
      );
      expect(await bank.get('s2_nothing', subgoalId: 's2'), isNull);
    });

    test('listServable (#186) reads the questions of one subgoal that may '
        'be served', () async {
      final shown = _code('Maak x vijf.');
      final hidden = _code('Maak x tien.');
      for (final q in [shown, hidden, _mcq(subgoalId: 's2')]) {
        await bank.recordAsked(q);
      }
      await bank.setHidden(hidden, true);

      expect((await bank.listServable('s1'))!.map((q) => q.id), [shown.id]);
      expect(await bank.listServable('s3'), isEmpty);
    });

    test(
      'listServable gives up on a bank that does not answer in time and '
      'leaves it alone for a while; an ordinary error is only logged',
      () async {
        final hanging = _QueryContainer(
          store.container,
          () => Completer<List<Map<String, dynamic>>>().future,
        );
        final slowBank = QuestionBankService(
          container: hanging,
          now: () => now,
          readTimeout: const Duration(milliseconds: 20),
        );
        expect(await slowBank.listServable('s1'), isNull);
        expect(await slowBank.listServable('s1'), isNull);
        expect(hanging.queries, 1, reason: 'backed off after the timeout');
        now = now.add(kQuestionBankRetryAfter);
        expect(await slowBank.listServable('s1'), isNull);
        expect(hanging.queries, 2);

        final failing = _QueryContainer(
          store.container,
          () async => throw CosmosException(500, 'Internal Server Error'),
        );
        final failingBank = QuestionBankService(
          container: failing,
          now: () => now,
        );
        expect(await failingBank.listServable('s1'), isNull);
        expect(await failingBank.listServable('s1'), isNull);
        expect(failing.queries, 2, reason: 'no back-off for a passing error');
      },
    );

    test('listSummaries names every question with its subgoal, status and '
        'whether it was reviewed', () async {
      final a = _mcq();
      final b = _code('Maak x vijf.');
      final c = _mcq(subgoalId: 's2');
      for (final q in [a, b, c]) {
        await bank.recordAsked(q);
      }
      await bank.setHidden(b, true);
      await bank.markReviewed(c);

      final summaries = await bank.listSummaries();
      expect(
        {for (final s in summaries) s.id: (s.subgoalId, s.hidden, s.reviewed)},
        {
          a.id: ('s1', false, false),
          b.id: ('s1', true, true),
          c.id: ('s2', false, true),
        },
      );
    });
  });

  group('teacher actions', () {
    test('mark reviewed, hide, show again and a note each stamp the review, '
        'and never delete', () async {
      final q = _mcq();
      await bank.recordAsked(q);

      final reviewed = await bank.markReviewed(q);
      expect(reviewed.reviewedAt, now);
      expect(reviewed.isActive, isTrue);

      now = now.add(const Duration(minutes: 5));
      final hidden = await bank.setHidden(reviewed, true);
      expect(hidden.isActive, isFalse);
      expect(hidden.reviewedAt, now);
      expect(store[q.id]!['status'], 'hidden');

      final shown = await bank.setHidden(hidden, false);
      expect(shown.isActive, isTrue);

      final noted = await bank.setNote(shown, '  Te makkelijk voor "hard".  ');
      expect(noted.teacherNote, 'Te makkelijk voor "hard".');
      expect(store[q.id]!['teacherNote'], 'Te makkelijk voor "hard".');

      final cleared = await bank.setNote(noted, ' ');
      expect(cleared.teacherNote, isNull);
      expect(store[q.id]!.containsKey('teacherNote'), isFalse);
      expect(store.docs, hasLength(1));
    });

    test('an action returns the counts students added since the page '
        'loaded, and does not roll them back', () async {
      final q = _mcq();
      await bank.recordAsked(q);
      final onScreen = BankQuestion.tryFromCosmos(store[q.id]!)!;

      await bank.recordAsked(q);
      await bank.recordAnswer(questionId: q.id, subgoalId: 's1', correct: true);

      final hidden = await bank.setHidden(onScreen, true);
      expect(hidden.askedCount, 2);
      expect(hidden.answeredCount, 1);
      expect(store[q.id]!['askedCount'], 2);
    });

    test('an action on a question that is gone throws', () async {
      await expectLater(bank.markReviewed(_mcq()), throwsStateError);
    });
  });
}
