import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';

/// Resolves a [ChatNotice] emitted by the service layer to the text shown in
/// a chat system pill (issue #23). The only place these strings are chosen.
extension ChatNoticeText on AppLocalizations {
  String chatNotice(ChatNotice n) {
    String arg(int i) => i < n.args.length ? n.args[i] : '';
    switch (n.kind) {
      case ChatNoticeKind.tutorFailed:
        return chat_notice_tutorFailed(_causeText(n));
      case ChatNoticeKind.sessionStartFailed:
        return chat_notice_sessionStartFailed(_causeText(n));
      case ChatNoticeKind.databaseUnavailable:
        return chat_notice_databaseUnavailable;
      case ChatNoticeKind.tutorTimeout:
        return chat_notice_tutorTimeout;
      case ChatNoticeKind.tutorUnreachable:
        return chat_notice_tutorUnreachable;
      case ChatNoticeKind.replyTruncated:
        return chat_notice_replyTruncated;
      case ChatNoticeKind.noPreviousRequest:
        return chat_notice_noPreviousRequest;
      case ChatNoticeKind.emptyResponse:
        return chat_notice_emptyResponse;
      case ChatNoticeKind.unparseableResponse:
        return chat_notice_unparseableResponse(arg(0));
      case ChatNoticeKind.unknownResponseType:
        return chat_notice_unknownResponseType(arg(0));
      case ChatNoticeKind.unknownResponse:
        return chat_notice_unknownResponse;
      case ChatNoticeKind.exerciseWithoutBlank:
        return chat_notice_exerciseWithoutBlank;
      case ChatNoticeKind.subgoalDeletedRedirect:
        return chat_notice_subgoalDeletedRedirect;
      case ChatNoticeKind.subgoalSaturated:
        return chat_notice_subgoalSaturated;
      case ChatNoticeKind.noGoalsLeft:
        return chat_notice_noGoalsLeft;
      case ChatNoticeKind.emptyObjectives:
        return chat_notice_emptyObjectives;
      case ChatNoticeKind.preparingExercise:
        return chat_notice_preparingExercise;
      case ChatNoticeKind.feedbackDegraded:
        return chat_notice_feedbackDegraded;
      case ChatNoticeKind.newGoalSelected:
        return chat_notice_newGoalSelected(arg(0));
      case ChatNoticeKind.difficultyChanged:
        return chat_notice_difficultyChanged(
          difficultyName(arg(0)),
          difficultyName(arg(1)),
        );
      case ChatNoticeKind.submitViaEditor:
        return chat_notice_submitViaEditor;
      case ChatNoticeKind.raw:
        return arg(0);
    }
  }

  String _causeText(ChatNotice n) {
    final cause = n.cause;
    if (cause != null) return chatNotice(cause);
    return n.args.isEmpty ? '' : n.args.first;
  }

  /// Localized name for a `QuestionDifficulty.name`; unknown names pass
  /// through unchanged.
  String difficultyName(String name) {
    if (name == QuestionDifficulty.easy.name) return difficulty_easy;
    if (name == QuestionDifficulty.medium.name) return difficulty_medium;
    if (name == QuestionDifficulty.hard.name) return difficulty_hard;
    return name;
  }
}
