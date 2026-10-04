// One question of the question bank (#185): a question the tutor generated
// for a student, kept so the conductor can ask it again without generating
// it (#186).
//
// The students do the weeding (#215): a generated question is stored only
// when the first answer to it is graded correct, and a stored one hides
// itself once too few answers to it are correct
// (`PolicyConstants.bankAutoHideMinAnswers` / `bankAutoHideMaxShare`). A
// question in the bank is approved by being there; the teacher hides, shows
// again or deletes what is still off.
//
// A doc in the `questions` container (`/subgoalId` partition):
//
//   - what it is for: `subgoalId`, `rootGoalId`, `targetLOIds`,
//     `questionType` (the `ChatRequestType` name, as on a turn record),
//     `difficulty`, `language`;
//   - `payload`: the question as the UI renders it — the META of the
//     generation with the TEXT under `prompt` (`ChatResponse.toJson`), plus,
//     for a multiple-choice question, `correct`: the intended answer as the
//     text of an option, not as a letter, since the options are shuffled;
//   - where it came from: `model`, `createdAt`, `createdByUid` (the student
//     who got it first; never shown);
//   - how it did: `askedCount` (times put in front of a student),
//     `answeredCount` (answers graded — a question can be left unanswered),
//     `correctCount` (of those, graded correct), `lastAskedAt`;
//   - `optionFeedback`: per multiple-choice option a student picked, the
//     feedback text the grader gave and the verdict it came with;
//   - `keyDisputedCount`, `keyDisputedAt`: how often the grader of a pick
//     said the answer key itself is wrong, and the last time (#198);
//   - `status` (`active` | `hidden`); for a hidden one `hiddenBy` (`teacher`
//     | `auto`, #215 — absent on a question hidden before #215, which was
//     the teacher) and `hiddenAt`; `keptByTeacher`: the teacher showed it
//     again after it hid itself, so it does not hide itself again.
//
// The doc id is `${subgoalId}_${contentHash}` — the same generation for the
// same subgoal is the same doc, and the id alone names the question, which
// is what a turn record's `questionId` holds. Nothing reads a question doc
// through a turn record — the tutor uses the ids only to not give a student
// the same question twice, the evaluation tooling only the turn record's own
// fields — so the teacher can delete a question; the same generation later
// gets the same id and has to pass its first answer again.

import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// `status` of a bank question. A hidden one stays in the container until
/// the teacher deletes it, but is not served (#186).
enum BankQuestionStatus { active, hidden }

/// Who hid a hidden bank question (#215): the teacher on the Questions
/// page, or the bank itself when too few answers to it were correct.
enum BankHiddenBy { teacher, auto }

/// The grader's feedback on one multiple-choice option, kept the first time
/// a student picks it (#185) so a later pick of the same option can be
/// answered without a model call (#186).
class BankOptionFeedback {
  const BankOptionFeedback({
    required this.option,
    required this.text,
    this.quality,
  });

  /// The option's text, as in `payload.options`.
  final String option;

  /// The feedback the student saw.
  final String text;

  /// The verdict the text was written for. Whoever reuses [text] should
  /// check it agrees with the answer key: a text that congratulates on a
  /// pick the key calls wrong must not be shown next to a red verdict.
  final AnswerQuality? quality;

  Map<String, dynamic> toJson() => {
    'option': option,
    'text': text,
    if (quality != null) 'quality': quality!.name,
  };

  static BankOptionFeedback? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final option = raw['option'];
    final text = raw['text'];
    if (option is! String || text is! String) return null;
    return BankOptionFeedback(
      option: option,
      text: text,
      quality: AnswerQuality.values.firstWhereOrNull(
        (q) => q.name == raw['quality'],
      ),
    );
  }
}

class BankQuestion {
  const BankQuestion({
    required this.id,
    required this.subgoalId,
    required this.rootGoalId,
    required this.targetLOIds,
    required this.questionType,
    required this.difficulty,
    required this.language,
    required this.payload,
    required this.model,
    required this.createdAt,
    required this.createdByUid,
    this.askedCount = 0,
    this.answeredCount = 0,
    this.correctCount = 0,
    this.lastAskedAt,
    this.optionFeedback = const [],
    this.keyDisputedCount = 0,
    this.keyDisputedAt,
    this.status = BankQuestionStatus.active,
    this.hiddenBy,
    this.hiddenAt,
    this.keptByTeacher = false,
  });

  /// `type` discriminator on every doc, like the other containers carry.
  static const String docType = 'question';

  final String id;
  final String subgoalId;
  final String rootGoalId;
  final List<String> targetLOIds;
  final ChatRequestType questionType;
  final QuestionDifficulty difficulty;

  /// The language the question is written in (`nl`, `en`, #117).
  final String language;
  final Map<String, dynamic> payload;
  final String model;
  final DateTime createdAt;
  final String createdByUid;
  final int askedCount;
  final int answeredCount;
  final int correctCount;
  final DateTime? lastAskedAt;
  final List<BankOptionFeedback> optionFeedback;

  /// How many gradings said the answer key itself is wrong (#198, META
  /// `keyDisputed`), whichever option the student had picked.
  final int keyDisputedCount;

  /// The last time one did; `null` when none ever has.
  final DateTime? keyDisputedAt;
  final BankQuestionStatus status;

  /// Who hid it, as the doc says; `null` on an active question and on one
  /// hidden before #215 (the teacher then).
  final BankHiddenBy? hiddenBy;

  /// When it was hidden; `null` on an active question.
  final DateTime? hiddenAt;

  /// The teacher showed it again after it hid itself (#215): it does not
  /// hide itself again.
  final bool keptByTeacher;

  bool get isActive => status == BankQuestionStatus.active;

  /// Hidden by the bank itself (#215), not by the teacher.
  bool get isAutoHidden => !isActive && hiddenBy == BankHiddenBy.auto;

  /// Correct answers per graded answer; `null` before the first one.
  double? get shareCorrect =>
      answeredCount == 0 ? null : correctCount / answeredCount;

  /// The response type as the model named it (`multiple_choice`, …).
  String get payloadType => (payload['type'] as String?) ?? '';
  String get prompt => (payload['prompt'] as String?) ?? '';
  String get code => (payload['code'] as String?) ?? '';
  bool get isMultipleChoice => payloadType == 'multiple_choice';

  /// The options in the order they were generated — not the order any
  /// student saw them in.
  List<String> get options => [
    for (final o in (payload['options'] as List?) ?? const [])
      if (o is Map && o['option'] is String) o['option'] as String,
  ];

  /// The answer key of a multiple-choice question, as option text.
  String? get correctOption => payload['correct'] as String?;

  BankOptionFeedback? feedbackFor(String option) =>
      optionFeedback.firstWhereOrNull((f) => f.option == option);

  /// Whether the grader ever judged a pick differently from the answer key
  /// — the key's own option graded less than correct, or another one
  /// graded correct — or said the key is wrong ([keyDisputedCount], #198):
  /// the one sign of a wrong key when the pick was another wrong option,
  /// which grade and key agree on. A sign the question — or its key — is
  /// off.
  bool get graderDisagreesWithKey {
    final key = correctOption;
    if (key == null) return false;
    if (keyDisputedCount > 0) return true;
    return optionFeedback.any((f) {
      final q = f.quality;
      if (q == null) return false;
      return f.option == key
          ? q != AnswerQuality.correct
          : q == AnswerQuality.correct;
    });
  }

  /// The question as the response the tutor dispatches (#186): a bank
  /// question goes through the same handler as a fresh one. `null` for a
  /// payload no handler takes.
  ChatResponse? toChatResponse() {
    if (isMultipleChoice) {
      // Built directly: `MultipleChoice.fromMap` reads `correct` as a
      // position first, and a stored key is option *text*.
      return MultipleChoice(
        type: payloadType,
        prompt: prompt,
        code: code,
        options: options,
        correct: correctOption,
      );
    }
    try {
      final response = ChatResponseFactory.fromMap(
        Map<String, dynamic>.from(payload),
      );
      return questionTypeFor(response) == null ? null : response;
    } catch (_) {
      return null;
    }
  }

  // ---- Building one from a generation ------------------------------------

  /// The request type a question response answers, or `null` when
  /// [response] is not a question. Taken from what the model *returned*,
  /// not what was asked for: a bank question is served as what it is.
  static ChatRequestType? questionTypeFor(ChatResponse response) =>
      switch (response) {
        MultipleChoice() => ChatRequestType.mcQuestion,
        CompleteCode() => ChatRequestType.completeCodeQuestion,
        ExplainCode() => ChatRequestType.explainCodeQuestion,
        WriteCode() => ChatRequestType.writeCodeQuestion,
        SocraticQuestion() => ChatRequestType.socraticQuestion,
        _ => null,
      };

  /// What the bank stores of [response]: its `toJson` (the META with the
  /// TEXT as `prompt`), plus the answer key of a multiple-choice question.
  static Map<String, dynamic> payloadOf(ChatResponse response) => {
    ...response.toJson(),
    if (response is MultipleChoice && response.correct != null)
      'correct': response.correct,
  };

  /// The dedupe key of a question (#185): a hash of its type, code and
  /// options. The options are sorted, so the same options in another order
  /// are the same question. A question without options (everything but
  /// multiple choice) is its prompt — `print(___)` is the code of many a
  /// different exercise — so there the prompt joins the hash, whitespace
  /// collapsed.
  static String contentHash({
    required String payloadType,
    required String code,
    required List<String> options,
    required String prompt,
  }) {
    final sorted = options.map((o) => o.trim()).toList()..sort();
    final canonical = jsonEncode({
      'type': payloadType,
      'code': code.trim(),
      'options': sorted,
      if (sorted.isEmpty) 'prompt': prompt.replaceAll(RegExp(r'\s+'), ' '),
    });
    return sha256.convert(utf8.encode(canonical)).toString().substring(0, 32);
  }

  static String idFor({required String subgoalId, required String hash}) =>
      '${subgoalId}_$hash';

  /// The bank entry for [response], asked on [subgoalId] at [createdAt] —
  /// or `null` when [response] is not a question. Counters start at zero:
  /// the bank stores it, ask and answer counted, only when the first answer
  /// to it is correct (`QuestionBankService.recordFirstAnswer`, #215).
  static BankQuestion? fromResponse(
    ChatResponse response, {
    required String subgoalId,
    required String rootGoalId,
    required List<String> targetLOIds,
    required QuestionDifficulty difficulty,
    required String language,
    required String model,
    required String createdByUid,
    required DateTime createdAt,
  }) {
    final questionType = questionTypeFor(response);
    if (questionType == null) return null;
    final payload = payloadOf(response);
    final options = [
      for (final o in (payload['options'] as List?) ?? const [])
        if (o is Map && o['option'] is String) o['option'] as String,
    ];
    final hash = contentHash(
      payloadType: response.type,
      code: (payload['code'] as String?) ?? '',
      options: options,
      prompt: (payload['prompt'] as String?) ?? '',
    );
    return BankQuestion(
      id: idFor(subgoalId: subgoalId, hash: hash),
      subgoalId: subgoalId,
      rootGoalId: rootGoalId,
      targetLOIds: List.unmodifiable(targetLOIds),
      questionType: questionType,
      difficulty: difficulty,
      language: language,
      payload: payload,
      model: model,
      createdAt: createdAt.toUtc(),
      createdByUid: createdByUid,
    );
  }

  // ---- Cosmos --------------------------------------------------------------

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': docType,
    'subgoalId': subgoalId,
    'rootGoalId': rootGoalId,
    'targetLOIds': targetLOIds,
    'questionType': questionType.name,
    'difficulty': difficulty.name,
    'language': language,
    'payload': payload,
    'model': model,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'createdByUid': createdByUid,
    'askedCount': askedCount,
    'answeredCount': answeredCount,
    'correctCount': correctCount,
    if (lastAskedAt != null)
      'lastAskedAt': lastAskedAt!.toUtc().toIso8601String(),
    'optionFeedback': optionFeedback.map((f) => f.toJson()).toList(),
    if (keyDisputedCount > 0) 'keyDisputedCount': keyDisputedCount,
    if (keyDisputedAt != null)
      'keyDisputedAt': keyDisputedAt!.toUtc().toIso8601String(),
    'status': status.name,
    if (hiddenBy != null) 'hiddenBy': hiddenBy!.name,
    if (hiddenAt != null) 'hiddenAt': hiddenAt!.toUtc().toIso8601String(),
    if (keptByTeacher) 'keptByTeacher': true,
  };

  /// A doc as `toMap` wrote it, or `null` when it is not one a later reader
  /// can use (no id or subgoal, a question type this build does not know).
  static BankQuestion? tryFromCosmos(Map<String, dynamic> doc) {
    final id = doc['id'];
    final subgoalId = doc['subgoalId'];
    final questionType = ChatRequestType.values.firstWhereOrNull(
      (t) => t.name == doc['questionType'],
    );
    final payload = doc['payload'];
    if (id is! String ||
        subgoalId is! String ||
        questionType == null ||
        payload is! Map) {
      return null;
    }
    DateTime? date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    int count(Object? raw) => raw is num ? raw.toInt() : 0;
    return BankQuestion(
      id: id,
      subgoalId: subgoalId,
      rootGoalId: (doc['rootGoalId'] as String?) ?? '',
      targetLOIds: [
        for (final lo in (doc['targetLOIds'] as List?) ?? const [])
          if (lo is String) lo,
      ],
      questionType: questionType,
      difficulty:
          QuestionDifficulty.values.firstWhereOrNull(
            (d) => d.name == doc['difficulty'],
          ) ??
          QuestionDifficulty.medium,
      language: (doc['language'] as String?) ?? '',
      payload: Map<String, dynamic>.from(payload),
      model: (doc['model'] as String?) ?? '',
      createdAt: date(doc['createdAt']) ?? DateTime.utc(1970),
      createdByUid: (doc['createdByUid'] as String?) ?? '',
      askedCount: count(doc['askedCount']),
      answeredCount: count(doc['answeredCount']),
      correctCount: count(doc['correctCount']),
      lastAskedAt: date(doc['lastAskedAt']),
      optionFeedback: [
        for (final f in (doc['optionFeedback'] as List?) ?? const [])
          ?BankOptionFeedback.tryFromJson(f),
      ],
      keyDisputedCount: count(doc['keyDisputedCount']),
      keyDisputedAt: date(doc['keyDisputedAt']),
      status: doc['status'] == BankQuestionStatus.hidden.name
          ? BankQuestionStatus.hidden
          : BankQuestionStatus.active,
      hiddenBy: BankHiddenBy.values.firstWhereOrNull(
        (b) => b.name == doc['hiddenBy'],
      ),
      hiddenAt: date(doc['hiddenAt']),
      keptByTeacher: doc['keptByTeacher'] == true,
    );
  }
}
