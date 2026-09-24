// Serving from the question bank (#186, CONDUCTOR_POLICY §2.7): whether the
// question a plan asks for comes out of the bank instead of a generation
// call, and which one.
//
// Pure policy. The conductor's plan says what to ask (subgoal, target LO,
// type, difficulty); the tutor reads the bank and the questions this student
// already answered, and hands them in here. Keeping the rule out of the
// tutor's IO keeps it testable on its own and in one place — the knobs are
// `PolicyConstants.bankMinimum` / `bankShare`, overridden per school in
// `config/global`.

import 'dart:math';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';

/// The school's mix (#186): how many fitting, unseen questions the bank must
/// hold for an ordinary plan ([minimum], N) and the chance that such a plan
/// is then served from it ([share], p).
class BankMix {
  const BankMix({
    this.minimum = PolicyConstants.bankMinimum,
    this.share = PolicyConstants.bankShare,
  });

  /// `QuestionBankMinimum` and `QuestionBankShare` of `config/global`, each
  /// falling back to its default when the school set none.
  factory BankMix.fromConfig(GlobalConfig? config) => BankMix(
    minimum: config?.questionBankMinimum ?? PolicyConstants.bankMinimum,
    share: config?.questionBankShare ?? PolicyConstants.bankShare,
  );

  final int minimum;
  final double share;
}

/// What [BankChoice.pick] found: the question to serve, or `null` when the
/// plan is generated — with how many questions fitted, for the debug log.
typedef BankPick = ({BankQuestion? question, int eligible});

class BankChoice {
  BankChoice._();

  /// The question types the bank serves. Multiple choice is graded from its
  /// answer key; the three code types are graded by the model as a fresh
  /// question is (#186). A socratic question is not served: it is an
  /// umbrella for dialogue openers (§1.1) that lean on the moment they are
  /// asked in, and the issue leaves it to generation.
  static const Set<ChatRequestType> servedTypes = {
    ChatRequestType.mcQuestion,
    ChatRequestType.completeCodeQuestion,
    ChatRequestType.explainCodeQuestion,
    ChatRequestType.writeCodeQuestion,
  };

  /// Whether [plan] may come from the bank at all: a type the bank serves,
  /// one target LO, and a school that did not switch serving off (a share
  /// of 0).
  static bool mayServe(QuestionPlan plan, BankMix mix) =>
      mix.share > 0 &&
      servedTypes.contains(plan.type) &&
      plan.targetLOs.isNotEmpty;

  /// The minimum that applies to [plan]: the school's N for an ordinary
  /// question; one for a warm-up review (§1.5) or a recheck (§2.6), which
  /// are taken from the bank whenever it has one.
  static int minimumFor(QuestionPlan plan, BankMix mix) =>
      plan.isOffSubgoal ? PolicyConstants.bankMinimumOffSubgoal : mix.minimum;

  /// The mix's roll for [plan]: whether it is to come from the bank if the
  /// bank holds enough. An ordinary question with the chance [BankMix.share];
  /// a warm-up review or a recheck — or any plan at a share of 1 — always,
  /// without a roll. Rolled before the bank is read: the same odds as
  /// rolling after the count, and a plan the roll gives to generation costs
  /// no read.
  static bool rollsForBank(QuestionPlan plan, BankMix mix, Random random) {
    if (!mayServe(plan, mix)) return false;
    if (plan.isOffSubgoal || mix.share >= 1) return true;
    return random.nextDouble() < mix.share;
  }

  /// Whether [q] is what [plan] asks for, on [subgoalId] (the plan's target
  /// subgoal: the active one, or the older one of a warm-up or recheck), in
  /// the student's [language].
  static bool fits(
    BankQuestion q, {
    required QuestionPlan plan,
    required String subgoalId,
    required String language,
  }) {
    final lo = plan.targetLOs.firstOrNull;
    return lo != null &&
        q.isActive &&
        q.subgoalId == subgoalId &&
        q.questionType == plan.type &&
        q.difficulty == plan.difficulty &&
        q.targetLOIds.contains(lo.id) &&
        q.language == language;
  }

  /// Whether [q] can be put in front of a student as it is stored: a payload
  /// a handler takes and, for multiple choice, an answer key that is one of
  /// its options and that the grader never contradicted
  /// (`graderDisagreesWithKey`) — a key the grading doubted is not one to
  /// grade by. The teacher sees those on the Questions page.
  static bool servable(BankQuestion q) {
    if (q.toChatResponse() == null) return false;
    if (!q.isMultipleChoice) return true;
    final key = q.correctOption;
    return key != null &&
        q.options.length >= 2 &&
        q.options.contains(key) &&
        !q.graderDisagreesWithKey;
  }

  /// The question to serve for [plan] out of [bank], or none.
  ///
  /// Eligible: fits the plan ([fits]), [servable], and new to this student
  /// — not in [alreadyAsked] (the ids on their turn records, and the
  /// questions this session put in front of them) and not one they got
  /// first ([uid] is its `createdByUid`). With fewer than [minimum]
  /// eligible, none. Otherwise the least recently asked — across the
  /// school, which during a lesson is the class — so the students of one
  /// class do not all get the same question; then the least asked; then the
  /// id, so the choice is stable.
  static BankPick pick({
    required QuestionPlan plan,
    required String subgoalId,
    required Iterable<BankQuestion> bank,
    required Set<String> alreadyAsked,
    required String uid,
    required String language,
    required int minimum,
  }) {
    final eligible = [
      for (final q in bank)
        if (fits(q, plan: plan, subgoalId: subgoalId, language: language) &&
            !alreadyAsked.contains(q.id) &&
            q.createdByUid != uid &&
            servable(q))
          q,
    ];
    if (eligible.isEmpty || eligible.length < minimum) {
      return (question: null, eligible: eligible.length);
    }
    final never = DateTime.utc(0);
    eligible.sort((a, b) {
      final byAsked = (a.lastAskedAt ?? never).compareTo(
        b.lastAskedAt ?? never,
      );
      if (byAsked != 0) return byAsked;
      final byCount = a.askedCount.compareTo(b.askedCount);
      if (byCount != 0) return byCount;
      return a.id.compareTo(b.id);
    });
    return (question: eligible.first, eligible: eligible.length);
  }
}
