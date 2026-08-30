enum ChatRequestType {
  socraticQuestion,
  mcQuestion,
  explainCodeQuestion,
  completeCodeQuestion,
  writeCodeQuestion,
  submitCode,
  mcqAnswer,
  requestHint,
  studentQuestion,
  explainAnswer,
  socraticFeedback,

  /// Grading call for a chained follow-up answer (CONDUCTOR_POLICY §6 /
  /// LLM_CONTRACT "Grading follow-up answers"). Reuses the standard grader
  /// payload; the conductor caps signal strength at `weak` and treats the
  /// effective difficulty as `medium` regardless of the original probe.
  followUpAnswer,
  status,
  noResult,
}
