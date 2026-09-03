// The AI-written justification of a grade proposal (#99, PUNTENFORMULE
// §2.6): the model writes the narrative *around* the computed number, from
// the student's status reports in the grading window and the quantitative
// trajectory in `progress_history`. It never picks the number — the prompt
// hands it the number as a fixed fact and forbids an own verdict on it, and
// the app stores the text next to the number it was written for, so a
// persuasive paragraph can never move a grade (§3.3).

import 'dart:convert';

import 'grade_proposal.dart';
import 'milestone.dart';

/// One status report the model may cite: the subgoal it is about, the text
/// and when it was written.
typedef JustificationReport = ({String title, String text, DateTime? at});

/// One subgoal's progress fraction at the start and end of the window.
typedef JustificationTrajectory = ({String title, double start, double end});

class JustificationPrompt {
  const JustificationPrompt({required this.instructions, required this.input});

  /// System prompt.
  final String instructions;

  /// User turn: the facts, as JSON.
  final String input;
}

String _languageName(String languageCode) {
  switch (languageCode) {
    case 'nl':
      return 'Dutch (Nederlands)';
    default:
      return 'English';
  }
}

/// Builds the two halves of the request. Everything the model is allowed to
/// draw on is in [input]; [instructions] carries the contract.
JustificationPrompt buildJustificationPrompt({
  required GradeProposal proposal,
  required Milestone milestone,
  required String studentName,
  required String calibrationLevel,
  required List<JustificationReport> reports,
  required List<JustificationTrajectory> trajectory,
  required String languageCode,
}) {
  final language = _languageName(languageCode);
  final instructions =
      '''
You write the justification that accompanies a report-card grade proposal for a secondary-school Python course. The teacher reads it before signing the grade off.

THE NUMBER IS FIXED. The proposal of ${proposal.proposal}/100 was computed by a published, deterministic formula from the student's learning data. You do not choose, estimate, question, round, or recommend a grade, and you do not suggest that it should be higher or lower. Your job is to explain, from the evidence provided, *why* the underlying measurements are what they are.

Write in $language. Plain prose only: no JSON, no markdown headings, no bullet lists, no tags or envelopes. Two to four short paragraphs, addressed to the teacher, about the student in the third person by first name.

Ground every statement in the data you are given: the status reports written during the grading period and the progress trajectory per subgoal. Do not invent events. If the evidence is thin (few reports, stale beliefs, no supervised work), say so plainly — staleness and where the evidence was produced are the honest uncertainty signals; a small number of questions is not (the tutor stops asking once mastery is established).

The student's current difficulty level is context only ("works at the hard level"); it is not an input to the number and you must not present it as one.
''';

  final input = jsonEncode({
    'student': studentName,
    'milestone': {
      'title': milestone.title,
      'periodStart': milestone.periodStart.toUtc().toIso8601String(),
      'dueAt': milestone.dueAt.toUtc().toIso8601String(),
      'expectedDifficulty': milestone.expectedDifficulty.name,
    },
    'formula': {
      'version': proposal.formulaVersion,
      'proposal': proposal.proposal,
      'masteryScoreEnd': _round(proposal.mEnd),
      'masteryScoreStart': _round(proposal.mStart),
      'masteryScoreStartSource': proposal.mStartSource.name,
      'growth': _round(proposal.g),
      'coreMasteredAtLevel': '${proposal.coreCounted}/${proposal.coreTotal}',
      'extensionMastered':
          '${proposal.extensionMastered}/${proposal.extensionTotal}',
      'masteredDemonstratedAtHard':
          '${proposal.hardCount}/${proposal.masteredTotal}',
    },
    'reliability': {
      'staleLearningObjectives': proposal.staleLoCount,
      'neverProbedLearningObjectives': proposal.neverProbedCount,
      'supervisedTurnsInPeriod': proposal.supervisedTurns,
      'homeTurnsInPeriod': proposal.homeTurns,
    },
    'contextOnly': {'currentDifficultyLevel': calibrationLevel},
    'statusReportsInPeriod': [
      for (final r in reports)
        {
          'subgoal': r.title,
          if (r.at != null) 'writtenAt': r.at!.toUtc().toIso8601String(),
          'report': r.text,
        },
    ],
    'progressTrajectory': [
      for (final t in trajectory)
        {
          'subgoal': t.title,
          'atPeriodStart': _round(t.start),
          'now': _round(t.end),
        },
    ],
  });

  return JustificationPrompt(instructions: instructions, input: input);
}

double _round(double v) => (v * 1000).round() / 1000;

final RegExp _textEnvelope = RegExp(
  r'<TEXT>([\s\S]*?)</TEXT>',
  caseSensitive: false,
);

/// The justification as it is stored: the model was asked for plain prose,
/// but a model that has the tutor's envelope habit is not punished for it —
/// the `<TEXT>` body is taken and any `<META>` tail dropped.
String extractJustificationText(String raw) {
  final m = _textEnvelope.firstMatch(raw);
  if (m != null) return m.group(1)!.trim();
  return raw.trim();
}
