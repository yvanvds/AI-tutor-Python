import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The question bank id (#185) of the question in front of the student —
/// generated or from the bank — whose short ID (`BankQuestion.shortIdOf`)
/// the header of the exercise shows (#216), so the teacher can look the
/// question up on the Questions page. A doc id (`<subgoal>_<hash>`), or the
/// content hash alone when the tutor could not name the subgoal: both give
/// the same short ID.
///
/// `null` while there is no question, and for a kind the bank does not
/// keep (a socratic question). Set when the question comes in and cleared
/// when the next one is planned: the hints, the grade and a follow-up in the
/// chat belong to the same exercise and get no ID of their own.
final shownQuestionIdProvider = StateProvider<String?>((_) => null);
