// The question bank's reads and writes (#185), over the `questions`
// container (`/subgoalId` partition — see `CosmosPaths.questions`).
//
// What the bank keeps (#215): a generated question is stored only at the
// first graded answer to it, and only when that answer is correct
// ([recordFirstAnswer]); a stored one hides itself once at least
// `PolicyConstants.bankAutoHideMinAnswers` answers are graded and less than
// `bankAutoHideMaxShare` of them were correct, unless the teacher showed it
// again after that (`keptByTeacher`). The teacher hides, shows again or
// deletes the rest by hand.
//
// Two kinds of caller, two error contracts:
//
//   - The tutor, on a student's machine: [listServable] when it considers
//     serving a question from the bank (#186), [recordAsked] when a bank
//     question is put in front of the student, [recordAnswer] when the
//     answer to it is graded, [recordFirstAnswer] when the answer to a
//     question it just generated is. Best-effort, like the turn history: a
//     failure is logged and swallowed, never thrown, the tutor does not
//     wait for any write, and the read gives up after
//     [kQuestionBankReadTimeout] — a bank that is slow, down, or not created
//     yet must not break or delay an exercise. The writes of one app run are
//     queued, so they land in the order they were made.
//   - The teacher's Questions page: listing, hiding and deleting throw, so
//     the page can say what went wrong — in particular that the container
//     does not exist yet ([CosmosException.isContainerNotFound]).
//
// Every write but a create or a delete reads the doc, changes the fields it
// owns and writes the doc back whole — with the fields it does not know
// about still in it, so a newer build's fields survive an older build's
// write (#165). Two clients counting the same question in the same instant
// can lose one increment; the counts are a statistic, not a grade, and
// Cosmos' REST patch is not wired into the client.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the tutor leaves the bank alone after finding its container
/// missing: long enough not to spend two requests on every question of a
/// lesson, short enough that creating the container mid-lesson is picked up
/// without a restart.
const Duration kQuestionBankRetryAfter = Duration(minutes: 10);

/// The part of a bank question the Questions page's goal tree counts with.
typedef BankQuestionSummary = ({String id, String subgoalId, bool hidden});

/// How long the tutor waits for the bank before it generates the question
/// instead (#186). A bank read normally takes a fraction of this; one that
/// takes longer is a bank that does not answer, and the question must not
/// wait for it.
const Duration kQuestionBankReadTimeout = Duration(seconds: 2);

class QuestionBankService {
  QuestionBankService({
    CosmosContainer? container,
    DateTime Function()? now,
    this.readTimeout = kQuestionBankReadTimeout,
  }) : _containerOverride = container,
       _now = now ?? (() => DateTime.now().toUtc());

  final CosmosContainer? _containerOverride;
  final DateTime Function() _now;

  /// How long [listServable] waits (#186); a test shortens it.
  final Duration readTimeout;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.questions();

  /// The tail of the write queue. Never completes with an error: every
  /// queued write swallows its own.
  Future<void> _tail = Future<void>.value();

  /// Until when the tutor skips the bank after a `ContainerNotFound`.
  DateTime? _unavailableUntil;

  /// Whether [answered] graded answers of which [correct] were correct hide
  /// a bank question (#215): at least `bankAutoHideMinAnswers` answers and
  /// less than `bankAutoHideMaxShare` correct. Exactly that share stays.
  static bool hidesItself({required int answered, required int correct}) =>
      answered >= PolicyConstants.bankAutoHideMinAnswers &&
      correct / answered < PolicyConstants.bankAutoHideMaxShare;

  // ---- Tutor side: best-effort, queued -------------------------------------

  /// Counts one ask of [question], served from the bank (#186): one more on
  /// its `askedCount`, and `lastAskedAt`. A question the bank no longer has
  /// — the teacher deleted it since it was read — is left alone: only a
  /// correct first answer stores a question ([recordFirstAnswer]).
  ///
  /// Never throws; the returned future is for tests; the tutor does not wait
  /// for it.
  Future<void> recordAsked(BankQuestion question) =>
      _queue('recordAsked ${question.id}', () async {
        final at = _now();
        await _modify(
          question.id,
          question.subgoalId,
          (doc) => _countAsk(doc, at),
        );
      });

  /// The first graded answer to [question], a question the tutor just
  /// generated (#215). [question] is as it was put in front of the student:
  /// its `createdAt` is when it was asked.
  ///
  /// When the bank does not have it yet, it is stored only when [correct] —
  /// a wrong or partial answer stores nothing — with the ask and the answer
  /// counted: `askedCount`, `answeredCount` and `correctCount` 1,
  /// `lastAskedAt` the moment it was asked, and for a multiple-choice pick
  /// the feedback the student got on it. When the bank has it already — the
  /// same generation, stored by another student's correct answer, also when
  /// that happened while this one was being created (a 409) — the ask and
  /// the answer count on that doc as they would on a served question,
  /// whatever the answer.
  ///
  /// [pickedOption], [feedback], [quality] and [keyDisputed] as for
  /// [recordAnswer]. Never throws.
  Future<void> recordFirstAnswer(
    BankQuestion question, {
    required bool correct,
    String? pickedOption,
    String? feedback,
    AnswerQuality? quality,
    bool keyDisputed = false,
  }) => _queue('recordFirstAnswer ${question.id}', () async {
    void count(Map<String, dynamic> doc) {
      _countAsk(doc, question.createdAt);
      _countAnswer(
        doc,
        correct: correct,
        pickedOption: pickedOption,
        feedback: feedback,
        quality: quality,
        keyDisputed: keyDisputed,
      );
    }

    final existing = await _container.read(
      question.id,
      partitionKey: question.subgoalId,
    );
    if (existing == null) {
      if (!correct) return;
      final doc = question.toMap();
      count(doc);
      try {
        await _container.create(doc, partitionKey: question.subgoalId);
        return;
      } on CosmosException catch (e) {
        // Another student's app stored the same generation first.
        if (e.statusCode != 409) rethrow;
      }
    }
    await _modify(question.id, question.subgoalId, count);
  });

  /// Counts one graded answer to the question [questionId], served from the
  /// bank: `answeredCount` always, `correctCount` when [correct]. For a
  /// multiple-choice pick, the grader's [feedback] on [pickedOption] is kept
  /// with its [quality] the first time that option is picked — a later text
  /// never replaces it. [keyDisputed]: the grader said the answer key itself
  /// is wrong (#198); counted in `keyDisputedCount`, the last time in
  /// `keyDisputedAt`. An answer that leaves the question with too few
  /// correct ([hidesItself]) hides it (#215).
  ///
  /// A question the bank no longer has is left alone. Never throws.
  Future<void> recordAnswer({
    required String questionId,
    required String subgoalId,
    required bool correct,
    String? pickedOption,
    String? feedback,
    AnswerQuality? quality,
    bool keyDisputed = false,
  }) => _queue('recordAnswer $questionId', () async {
    await _modify(
      questionId,
      subgoalId,
      (doc) => _countAnswer(
        doc,
        correct: correct,
        pickedOption: pickedOption,
        feedback: feedback,
        quality: quality,
        keyDisputed: keyDisputed,
      ),
    );
  });

  /// The questions of [subgoalId] the tutor may serve (#186): the active
  /// ones, as [listForSubgoal] reads them — or `null` when the bank cannot
  /// say. Best-effort like the writes: a missing container, a failure or a
  /// bank that does not answer within [readTimeout] is logged and swallowed,
  /// and the tutor generates the question instead. A missing container or
  /// a read that timed out leaves the bank alone — reads and writes — for
  /// [kQuestionBankRetryAfter], so the questions of a lesson do not each
  /// wait for it again.
  Future<List<BankQuestion>?> listServable(String subgoalId) async {
    if (!_available) return null;
    try {
      return await listForSubgoal(
        subgoalId,
        activeOnly: true,
      ).timeout(readTimeout);
    } on TimeoutException {
      _pause('the bank did not answer within ${readTimeout.inMilliseconds} ms');
    } on CosmosException catch (e) {
      if (e.isContainerNotFound) {
        _pause('no `questions` container — create it (README step 3). $e');
      } else {
        debugPrint('QuestionBankService: listServable failed: $e');
      }
    } catch (e) {
      debugPrint('QuestionBankService: listServable failed: $e');
    }
    return null;
  }

  /// Waits for every write queued so far. For tests.
  @visibleForTesting
  Future<void> get idle => _tail;

  Future<void> _queue(String what, Future<void> Function() write) {
    final run = _tail.then((_) => _bestEffort(what, write));
    _tail = run;
    return run;
  }

  bool get _available {
    final until = _unavailableUntil;
    return until == null || !_now().isBefore(until);
  }

  /// Leaves the bank alone for [kQuestionBankRetryAfter], and says why.
  void _pause(String why) {
    _unavailableUntil = _now().add(kQuestionBankRetryAfter);
    debugPrint(
      'QuestionBankService: $why — the question bank is not used for the '
      'next ${kQuestionBankRetryAfter.inMinutes} minutes.',
    );
  }

  Future<void> _bestEffort(String what, Future<void> Function() write) async {
    if (!_available) return;
    try {
      await safeCosmos(write);
    } on CosmosException catch (e) {
      if (e.isContainerNotFound) {
        _pause('no `questions` container — create it (README step 3). $e');
        return;
      }
      debugPrint('QuestionBankService: $what failed: $e');
    } catch (e) {
      debugPrint('QuestionBankService: $what failed: $e');
    }
  }

  /// One more ask on [doc], asked at [at]; `lastAskedAt` never goes back.
  static void _countAsk(Map<String, dynamic> doc, DateTime at) {
    doc['askedCount'] = _count(doc['askedCount']) + 1;
    final last = doc['lastAskedAt'] is String
        ? DateTime.tryParse(doc['lastAskedAt'] as String)
        : null;
    if (last == null || at.isAfter(last)) {
      doc['lastAskedAt'] = at.toUtc().toIso8601String();
    }
  }

  /// One more graded answer on [doc] (see [recordAnswer]), and the hide it
  /// may bring (#215).
  void _countAnswer(
    Map<String, dynamic> doc, {
    required bool correct,
    String? pickedOption,
    String? feedback,
    AnswerQuality? quality,
    bool keyDisputed = false,
  }) {
    final answered = _count(doc['answeredCount']) + 1;
    final right = _count(doc['correctCount']) + (correct ? 1 : 0);
    doc['answeredCount'] = answered;
    doc['correctCount'] = right;
    if (keyDisputed) {
      doc['keyDisputedCount'] = _count(doc['keyDisputedCount']) + 1;
      doc['keyDisputedAt'] = _now().toIso8601String();
    }
    if (doc['status'] != BankQuestionStatus.hidden.name &&
        doc['keptByTeacher'] != true &&
        hidesItself(answered: answered, correct: right)) {
      doc['status'] = BankQuestionStatus.hidden.name;
      doc['hiddenBy'] = BankHiddenBy.auto.name;
      doc['hiddenAt'] = _now().toIso8601String();
    }
    final text = feedback?.trim() ?? '';
    if (pickedOption == null || text.isEmpty) return;
    final question = BankQuestion.tryFromCosmos(doc);
    if (question == null || !question.options.contains(pickedOption)) {
      return;
    }
    if (question.feedbackFor(pickedOption) != null) return;
    doc['optionFeedback'] = [
      ...question.optionFeedback.map((f) => f.toJson()),
      BankOptionFeedback(
        option: pickedOption,
        text: text,
        quality: quality,
      ).toJson(),
    ];
  }

  // ---- Reads (#186 and the Questions page) ---------------------------------

  /// One question, or `null` when the bank does not have it. Throws.
  Future<BankQuestion?> get(String id, {required String subgoalId}) async {
    final doc = await safeCosmos(
      () => _container.read(id, partitionKey: subgoalId),
    );
    return doc == null ? null : BankQuestion.tryFromCosmos(doc);
  }

  /// Every question stored for [subgoalId] — one partition — newest first;
  /// only the ones that may be served when [activeOnly]. Throws.
  Future<List<BankQuestion>> listForSubgoal(
    String subgoalId, {
    bool activeOnly = false,
  }) async {
    final docs = await safeCosmos(
      () => _container.query(
        'SELECT * FROM c WHERE c.subgoalId = @sid',
        parameters: {'@sid': subgoalId},
        partitionKey: subgoalId,
      ),
    );
    final out = <BankQuestion>[
      for (final doc in docs)
        if (BankQuestion.tryFromCosmos(doc) case final q?)
          // Re-applied client-side: the in-memory fake and a partial index
          // must not widen the list.
          if (q.subgoalId == subgoalId && (!activeOnly || q.isActive)) q,
    ];
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// What the Questions page's goal tree counts: every question's subgoal
  /// and whether it is hidden. The one read that crosses partitions;
  /// teacher-only. Throws.
  Future<List<BankQuestionSummary>> listSummaries() async {
    final docs = await safeCosmos(
      () => _container.query(
        'SELECT c.id, c.subgoalId, c.status FROM c',
        crossPartition: true,
      ),
    );
    return [
      for (final doc in docs)
        if (doc['id'] case final String id)
          if (doc['subgoalId'] case final String subgoalId)
            (
              id: id,
              subgoalId: subgoalId,
              hidden: doc['status'] == BankQuestionStatus.hidden.name,
            ),
    ];
  }

  // ---- Teacher actions -----------------------------------------------------
  //
  // They throw.

  /// Hides [question] from being served, or ([hidden] false) lets it back
  /// in. Returns it as it now stands in the container — counts included
  /// that students added since the page loaded. Showing again a question
  /// that hid itself marks it `keptByTeacher` (#215): it does not hide
  /// itself again, or it would at the next answer.
  Future<BankQuestion> setHidden(BankQuestion question, bool hidden) async {
    final written = await safeCosmos(
      () => _modify(question.id, question.subgoalId, (doc) {
        if (hidden) {
          doc['status'] = BankQuestionStatus.hidden.name;
          doc['hiddenBy'] = BankHiddenBy.teacher.name;
          doc['hiddenAt'] = _now().toIso8601String();
          return;
        }
        if (doc['status'] == BankQuestionStatus.hidden.name &&
            doc['hiddenBy'] == BankHiddenBy.auto.name) {
          doc['keptByTeacher'] = true;
        }
        doc['status'] = BankQuestionStatus.active.name;
        doc
          ..remove('hiddenBy')
          ..remove('hiddenAt');
      }),
    );
    final updated = written == null
        ? null
        : BankQuestion.tryFromCosmos(written);
    if (updated == null) {
      throw StateError('Question ${question.id} is no longer in the bank.');
    }
    return updated;
  }

  /// Deletes [question] from the bank (#215) — hidden or not. Safe: turn
  /// records keep its id, but nothing reads the question through one (see
  /// `bank_question.dart`). The same generation, asked again later, gets the
  /// same id and is stored only when its first answer is correct. A question
  /// already gone is no error.
  Future<void> delete(BankQuestion question) => safeCosmos(
    () => _container.delete(question.id, partitionKey: question.subgoalId),
  );

  /// Reads the doc, applies [change] and writes it back. Returns what was
  /// written, or `null` when the doc does not exist.
  Future<Map<String, dynamic>?> _modify(
    String id,
    String subgoalId,
    void Function(Map<String, dynamic> doc) change,
  ) async {
    final doc = await _container.read(id, partitionKey: subgoalId);
    if (doc == null) return null;
    // Cosmos owns `_rid`, `_etag`, `_ts`…: not echoed back (as in
    // `GlobalConfigService.setModel`).
    doc.removeWhere((k, _) => k.startsWith('_'));
    change(doc);
    return _container.replace(id, doc, partitionKey: subgoalId);
  }

  static int _count(Object? raw) => raw is num ? raw.toInt() : 0;
}

final questionBankServiceProvider = Provider<QuestionBankService>(
  (ref) => QuestionBankService(),
);
