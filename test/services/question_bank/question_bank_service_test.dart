// Issues #185 and #215 — the question bank service over an in-memory
// `questions` container: a generated question stored only at a correct
// first answer, once however often it comes back; its asks and answers
// counted, the first feedback per option kept; a question hiding itself
// when too few answers are correct, unless the teacher kept it; the
// teacher's hide, show again and delete — and the two error contracts:
// best-effort on the student's side (a missing container is logged, never
// thrown, and left alone for a while), throwing on the teacher's.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

/// The multiple-choice question, asked at [at] (its `createdAt`).
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
    String? ifMatch,
  }) => _inner.replace(id, doc, partitionKey: partitionKey, ifMatch: ifMatch);

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

  /// [q] as the bank holds it after its first answer, with the counts given.
  void seed(
    BankQuestion q, {
    int asked = 1,
    int answered = 1,
    int correct = 1,
    Map<String, Object?> extra = const {},
  }) => store.upsert({
    ...q.toMap(),
    'askedCount': asked,
    'answeredCount': answered,
    'correctCount': correct,
    'lastAskedAt': q.createdAt.toIso8601String(),
    ...extra,
  });

  BankQuestion stored(String id) => BankQuestion.tryFromCosmos(store[id]!)!;

  group('recordFirstAnswer (#215)', () {
    test('a correct first answer stores the question with its ask and its '
        'answer counted, asked when it was asked, and the feedback on the '
        'pick', () async {
      final q = _mcq();
      await bank.recordFirstAnswer(
        q,
        correct: true,
        pickedOption: '2',
        feedback: 'Juist: 1 + 1 is 2.',
        quality: AnswerQuality.correct,
      );

      expect(store.docs.keys, [q.id]);
      final doc = store[q.id]!;
      expect(doc['type'], 'question');
      expect(doc['subgoalId'], 's1');
      expect(doc['status'], 'active');
      expect(doc['payload']['correct'], '2');
      expect(doc['askedCount'], 1);
      expect(doc['answeredCount'], 1);
      expect(doc['correctCount'], 1);
      expect(doc['createdAt'], '2026-09-24T08:00:00.000Z');
      expect(
        doc['lastAskedAt'],
        '2026-09-24T08:00:00.000Z',
        reason: 'the moment it was asked, not the moment it was answered',
      );
      expect(doc['optionFeedback'], [
        {'option': '2', 'text': 'Juist: 1 + 1 is 2.', 'quality': 'correct'},
      ]);
      expect(doc.containsKey('hiddenBy'), isFalse);
      expect(doc.containsKey('reviewedAt'), isFalse);
    });

    test('a wrong or partial first answer stores nothing', () async {
      await bank.recordFirstAnswer(
        _mcq(),
        correct: false,
        pickedOption: '11',
        feedback: 'Nee.',
        quality: AnswerQuality.wrong,
      );
      // `partial` reaches the service as not correct.
      await bank.recordFirstAnswer(_code('Maak x vijf.'), correct: false);
      expect(store.docs, isEmpty);
    });

    test('a question the bank already has counts the ask and the answer, '
        'whatever the answer; the first student\'s doc stays', () async {
      final q = _mcq();
      await bank.recordFirstAnswer(q, correct: true);

      // The same generation, asked of another student an hour later and
      // answered wrong.
      await bank.recordFirstAnswer(
        _mcq(at: DateTime.utc(2026, 9, 24, 9)),
        correct: false,
        pickedOption: '11',
        feedback: 'Nee.',
        quality: AnswerQuality.wrong,
      );

      expect(store.docs, hasLength(1));
      final doc = store[q.id]!;
      expect(doc['askedCount'], 2);
      expect(doc['answeredCount'], 2);
      expect(doc['correctCount'], 1);
      expect(doc['lastAskedAt'], '2026-09-24T09:00:00.000Z');
      expect(doc['createdAt'], '2026-09-24T08:00:00.000Z');
      expect((doc['optionFeedback'] as List).single['option'], '11');

      // One asked before the last ask: `lastAskedAt` does not go back.
      await bank.recordFirstAnswer(
        _mcq(at: DateTime.utc(2026, 9, 24, 7)),
        correct: true,
      );
      expect(store[q.id]!['lastAskedAt'], '2026-09-24T09:00:00.000Z');
      expect(store[q.id]!['askedCount'], 3);
    });

    test('a question another app stored in the meantime is counted, not '
        'overwritten', () async {
      final q = _mcq();
      final slow = _SlowContainer(store.container, holdCreates: true)
        ..hold = true;
      final racing = QuestionBankService(container: slow, now: () => now);
      final pending = racing.recordFirstAnswer(q, correct: true);
      await Future<void>.delayed(Duration.zero);
      // This app found no doc and is about to create it; another student's
      // app stores the same generation first, so the create hits a 409.
      await bank.recordFirstAnswer(q, correct: true);
      slow.release();
      await pending;

      expect(store.docs, hasLength(1));
      expect(store[q.id]!['askedCount'], 2);
      expect(store[q.id]!['answeredCount'], 2);
      expect(store[q.id]!['correctCount'], 2);
    });

    test("a newer build's fields on the doc survive the write", () async {
      final q = _mcq();
      await bank.recordFirstAnswer(q, correct: true);
      store.docs[q.id]!['futureField'] = 'keep me';

      await bank.recordFirstAnswer(q, correct: true);
      await bank.recordAsked(q);
      expect(store[q.id]!['futureField'], 'keep me');
    });
  });

  group('recordAsked', () {
    test('counts an ask of a stored question; a question the bank does not '
        'have — deleted since it was read — is not stored', () async {
      final q = _mcq();
      seed(q);

      now = DateTime.utc(2026, 9, 25, 10);
      await bank.recordAsked(q);
      expect(store[q.id]!['askedCount'], 2);
      expect(store[q.id]!['lastAskedAt'], '2026-09-25T10:00:00.000Z');

      await bank.recordAsked(_code('Maak x vijf.'));
      expect(store.docs.keys, [q.id]);
    });
  });

  group('recordAnswer', () {
    test('counts answers and correct answers, and keeps the first feedback '
        'per option with its verdict', () async {
      final q = _mcq();
      seed(q);

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

      final s = stored(q.id);
      expect(s.askedCount, 1);
      expect(s.answeredCount, 4);
      expect(s.correctCount, 2);
      expect(s.optionFeedback.map((f) => f.toJson()), [
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
      seed(q, answered: 0, correct: 0);
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

      final s = stored(q.id);
      expect(s.answeredCount, 2);
      expect(s.correctCount, 1);
      expect(s.optionFeedback, isEmpty);
    });

    test('a grading that called the key wrong is counted and stamped (#198); '
        'the question is then in doubt', () async {
      final q = _mcq();
      seed(q, answered: 0, correct: 0);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        pickedOption: 'Error',
        feedback: 'Nee.',
        quality: AnswerQuality.wrong,
      );
      expect(store[q.id]!.containsKey('keyDisputedCount'), isFalse);
      expect(
        stored(q.id).graderDisagreesWithKey,
        isFalse,
        reason: 'a wrong pick graded wrong agrees with the key',
      );

      now = DateTime.utc(2026, 9, 24, 11);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        pickedOption: '11',
        feedback: 'Nee: 1 + 1 is een som.',
        quality: AnswerQuality.wrong,
        keyDisputed: true,
      );
      now = DateTime.utc(2026, 9, 24, 12);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
        keyDisputed: true,
      );

      final s = stored(q.id);
      expect(s.answeredCount, 3);
      expect(s.keyDisputedCount, 2);
      expect(s.keyDisputedAt, DateTime.utc(2026, 9, 24, 12));
      expect(s.optionFeedback, hasLength(2));
      expect(s.graderDisagreesWithKey, isTrue);
    });

    test(
      'an answer to a question the bank does not have is left alone',
      () async {
        await bank.recordAnswer(
          questionId: 's1_unknown',
          subgoalId: 's1',
          correct: true,
        );
        expect(store.docs, isEmpty);
      },
    );

    test('the writes of one app land in the order they were made, however '
        'slow the bank is', () async {
      final slow = _SlowContainer(store.container)..hold = true;
      final queued = QuestionBankService(container: slow, now: () => now);
      final q = _mcq();

      final first = queued.recordFirstAnswer(q, correct: true);
      // Served again later in the same run, before the bank answered.
      final asked = queued.recordAsked(q);
      final answered = queued.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.docs, isEmpty, reason: 'the bank has not answered yet');

      slow.release();
      await Future.wait([first, asked, answered]);
      expect(store[q.id]!['askedCount'], 2);
      expect(store[q.id]!['answeredCount'], 2);
      expect(store[q.id]!['correctCount'], 2);
    });
  });

  group('a question hides itself (#215)', () {
    test('the thresholds are the policy\'s', () {
      expect(PolicyConstants.bankAutoHideMinAnswers, 10);
      expect(PolicyConstants.bankAutoHideMaxShare, 0.5);
      expect(QuestionBankService.hidesItself(answered: 10, correct: 4), isTrue);
      expect(
        QuestionBankService.hidesItself(answered: 10, correct: 5),
        isFalse,
      );
      expect(QuestionBankService.hidesItself(answered: 9, correct: 0), isFalse);
    });

    test('an answer that leaves at least 10 answers with less than half '
        'correct hides the question, saying who and when', () async {
      final q = _mcq();
      seed(q, asked: 12, answered: 9, correct: 4);
      expect(stored(q.id).isActive, isTrue, reason: '4/9, but only 9');

      now = DateTime.utc(2026, 9, 26, 9);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
      );

      final s = stored(q.id);
      expect(s.answeredCount, 10);
      expect(s.correctCount, 4);
      expect(s.isActive, isFalse);
      expect(s.isAutoHidden, isTrue);
      expect(store[q.id]!['hiddenBy'], 'auto');
      expect(s.hiddenAt, DateTime.utc(2026, 9, 26, 9));
      expect(await bank.listServable('s1'), isEmpty);
    });

    test('exactly half stays, and a share under half on fewer than 10 '
        'answers too', () async {
      final half = _mcq();
      final few = _code('Maak x vijf.');
      seed(half, answered: 9, correct: 5);
      seed(few, answered: 8, correct: 1);

      await bank.recordAnswer(
        questionId: half.id,
        subgoalId: 's1',
        correct: false,
      );
      await bank.recordAnswer(
        questionId: few.id,
        subgoalId: 's1',
        correct: false,
      );

      expect(stored(half.id).answeredCount, 10);
      expect(stored(half.id).isActive, isTrue, reason: '5/10 is half');
      expect(stored(few.id).isActive, isTrue, reason: '1/9 on 9 answers');
    });

    test('the first answer of another student counts toward it too', () async {
      final q = _mcq();
      seed(q, answered: 9, correct: 4);
      await bank.recordFirstAnswer(
        _mcq(at: DateTime.utc(2026, 9, 25)),
        correct: false,
      );
      expect(stored(q.id).isAutoHidden, isTrue);
    });

    test('shown again by the teacher, it is kept: it does not hide itself '
        'again', () async {
      final q = _mcq();
      seed(q, answered: 9, correct: 4);
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
      );
      expect(stored(q.id).isAutoHidden, isTrue);

      final shown = await bank.setHidden(stored(q.id), false);
      expect(shown.isActive, isTrue);
      expect(shown.keptByTeacher, isTrue);
      expect(store[q.id]!['keptByTeacher'], isTrue);
      expect(store[q.id]!.containsKey('hiddenBy'), isFalse);
      expect(store[q.id]!.containsKey('hiddenAt'), isFalse);

      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
      );
      expect(stored(q.id).answeredCount, 11);
      expect(stored(q.id).isActive, isTrue);
    });

    test('one the teacher hid stays hidden by the teacher', () async {
      final q = _mcq();
      seed(q, answered: 9, correct: 4);
      final hidden = await bank.setHidden(stored(q.id), true);
      final at = store[q.id]!['hiddenAt'];

      now = now.add(const Duration(days: 1));
      await bank.recordAnswer(
        questionId: q.id,
        subgoalId: 's1',
        correct: false,
      );
      expect(store[q.id]!['hiddenBy'], 'teacher');
      expect(store[q.id]!['hiddenAt'], at);
      expect(hidden.isAutoHidden, isFalse);
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
      await expectLater(
        bank.recordFirstAnswer(_mcq(), correct: true),
        completes,
      );
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
      await bank.recordFirstAnswer(_mcq(), correct: true);
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
        await bank.recordFirstAnswer(_mcq(), correct: true);
        expect(missing.requests.length, afterFirst);

        now = now.add(kQuestionBankRetryAfter);
        expect(await bank.listServable('s1'), isNull);
        expect(missing.requests.length, greaterThan(afterFirst));
      },
    );

    test(
      'the teacher side throws a ContainerNotFound the page can name',
      () async {
        Matcher notFound() => throwsA(
          isA<CosmosException>().having(
            (e) => e.isContainerNotFound,
            'isContainerNotFound',
            isTrue,
          ),
        );
        await expectLater(bank.listSummaries(), notFound());
        await expectLater(bank.listForSubgoal('s1'), notFound());
        await expectLater(bank.delete(_mcq()), notFound());
      },
    );
  });

  group('reads', () {
    test('listForSubgoal reads one subgoal, newest first, and can keep to the '
        'questions that may be served', () async {
      final older = _code('Maak x vijf.', at: DateTime.utc(2026, 9, 20));
      final newer = _code('Maak x tien.', at: DateTime.utc(2026, 9, 22));
      final elsewhere = _mcq(subgoalId: 's2');
      for (final q in [older, newer, elsewhere]) {
        seed(q);
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
        seed(q);
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

    test('listSummaries names every question with its subgoal and whether '
        'it is hidden', () async {
      final a = _mcq();
      final b = _code('Maak x vijf.');
      final c = _mcq(subgoalId: 's2');
      for (final q in [a, b, c]) {
        seed(q);
      }
      await bank.setHidden(b, true);
      // Hidden by the bank itself, and one from before #215 with a review
      // stamp: both counted for what they are.
      store.docs[c.id]!
        ..['status'] = 'hidden'
        ..['hiddenBy'] = 'auto'
        ..['reviewedAt'] = '2026-09-24T10:00:00.000Z';

      final summaries = await bank.listSummaries();
      expect(
        {for (final s in summaries) s.id: (s.subgoalId, s.hidden)},
        {a.id: ('s1', false), b.id: ('s1', true), c.id: ('s2', true)},
      );
    });
  });

  group('teacher actions', () {
    test('hide and show again say who hid it and when, and never touch the '
        'counts', () async {
      final q = _mcq();
      seed(q, asked: 3, answered: 2, correct: 1);

      now = DateTime.utc(2026, 9, 25, 14);
      final hidden = await bank.setHidden(stored(q.id), true);
      expect(hidden.isActive, isFalse);
      expect(hidden.hiddenBy, BankHiddenBy.teacher);
      expect(hidden.hiddenAt, now);
      expect(hidden.isAutoHidden, isFalse);
      expect(store[q.id]!['status'], 'hidden');
      expect(store[q.id]!.containsKey('reviewedAt'), isFalse);

      final shown = await bank.setHidden(hidden, false);
      expect(shown.isActive, isTrue);
      expect(shown.hiddenBy, isNull);
      expect(shown.hiddenAt, isNull);
      expect(
        shown.keptByTeacher,
        isFalse,
        reason: 'only a question that hid itself is marked kept',
      );
      expect(
        (shown.askedCount, shown.answeredCount, shown.correctCount),
        (3, 2, 1),
      );
    });

    test('an action returns the counts students added since the page '
        'loaded, and does not roll them back', () async {
      final q = _mcq();
      seed(q);
      final onScreen = stored(q.id);

      await bank.recordAsked(q);
      await bank.recordAnswer(questionId: q.id, subgoalId: 's1', correct: true);

      final hidden = await bank.setHidden(onScreen, true);
      expect(hidden.askedCount, 2);
      expect(hidden.answeredCount, 2);
      expect(store[q.id]!['askedCount'], 2);
    });

    test('an action on a question that is gone throws', () async {
      await expectLater(bank.setHidden(_mcq(), true), throwsStateError);
    });

    test('delete removes the question — hidden or not — and a question '
        'already gone is no error', () async {
      final a = _mcq();
      final b = _code('Maak x vijf.');
      seed(a);
      seed(b);
      await bank.setHidden(b, true);

      await bank.delete(a);
      await bank.delete(stored(b.id));
      expect(store.docs, isEmpty);
      await expectLater(bank.delete(a), completes);

      // The same generation, asked again later, is a new question: stored
      // only when its first answer is correct.
      await bank.recordFirstAnswer(a, correct: false);
      expect(store.docs, isEmpty);
      await bank.recordFirstAnswer(a, correct: true);
      expect(stored(a.id).answeredCount, 1);
    });
  });
}
