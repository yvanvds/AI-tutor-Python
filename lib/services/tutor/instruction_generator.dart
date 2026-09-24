import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';

/// Hard-coded envelope contract appended to every system prompt. Tells the
/// model to wrap student-facing markdown in `<TEXT>...</TEXT>` and the rest
/// of the structured payload (type + any code/options/quality/...) as JSON in
/// `<META>...</META>`. This lives outside teacher-editable instructions so
/// the transport contract can never be accidentally broken.
const String envelopeContract = '''
RESPONSE FORMAT — STRICT.
Every response must be wrapped in two sections, in this order:

<TEXT>
The student-facing markdown text (what would normally go in the "prompt" field). This is what the student reads. Do not put JSON or fenced code blocks containing JSON here. Plain markdown only.
</TEXT>
<META>
{"type":"<one of the response types>", ...all other structured fields except "prompt"}
</META>

Rules:
- Do not put any other content outside these two sections.
- Do not include the "prompt" field inside META — its value is the TEXT section.
- For status_summary the TEXT section may be the report itself; the rest of the stats stay in META.
- For multiple_choice keep "options" inside META.
- If the response would be of type "error", put the error message in TEXT and {"type":"error"} in META.
''';

/// The language a code stands for, spelled out for the model. Mirrors the
/// mapping in `grading/grade_justification.dart` (#99) so the tutor and the
/// grade justification never disagree about what `nl` means.
String _languageName(String languageCode) {
  switch (languageCode) {
    case 'nl':
      return 'Dutch (Nederlands)';
    default:
      return 'English';
  }
}

/// The output-language directive appended to every system prompt (#117).
///
/// The student picks a language in Options; until now that switched only the
/// interface, because the tutor's language was implicit in the
/// teacher-authored instruction bodies — which happen to be written in Dutch.
/// So this directive has to *override* the language those bodies are written
/// in, and it is appended last, after them, saying so in as many words.
///
/// It is scoped to student-facing prose only: META's JSON keys and enum
/// values, learning-objective ids and code are the machine half of the
/// contract (see `docs/LLM_CONTRACT.md`) and translating them would break
/// parsing and belief updates.
String languageDirective(String languageCode) {
  final language = _languageName(languageCode);
  return '''
OUTPUT LANGUAGE — STRICT. This overrides the language of every instruction above.
Write all student-facing text in $language: the entire TEXT section and every student-facing string inside META (questions, multiple-choice options, hints, feedback, explanations, status reports). The instructions above may themselves be written in another language; that is not a licence to answer in it.
Never translate the machine parts: META's JSON keys and enum values (including "type"), learning-objective ids, and the code, identifiers and API names in any snippet you show the student.
''';
}

/// How the grader of a multiple-choice pick treats the question's answer key
/// (#197, LLM_CONTRACT "The answer key"), appended to every `mcqAnswer`
/// system prompt after the teacher-authored bodies.
///
/// It lives outside the teacher-editable instructions, like
/// [envelopeContract], because the question bank depends on it: the bank
/// stops serving a question once a grade contradicts its key
/// (`graderDisagreesWithKey`, CONDUCTOR_POLICY §2.7), and a grader told to
/// follow the key would never contradict a wrong one. So the key is the
/// intended answer, but the grade stays the grader's own judgement.
const String answerKeyDirective = '''
ANSWER KEY — STRICT. This is part of the app's contract and holds whatever the instructions above say.
The request may carry `correct_option`: the option the question's author marked as the right one when the question was written, as the text of that option. It comes only with a pick the student has made; the student has not seen it.
- Take it as the intended answer: a pick equal to `correct_option` is what the question meant to be right, any other pick is not.
- Check it before you grade by it. If the key is wrong — the code does not do what the key says, the key does not answer the question, or another option is at least as right — grade the pick by what is actually right, not by the key.
- Your `overallQuality` is your own judgement of the pick: never adjust it to agree with the key. When your grade differs from the key, the app flags the question for the teacher; that is how a wrong key gets fixed.
- The key is for your judgement, not for the student. Never mention `correct_option`, an answer key or the author's intended answer, and when the pick is wrong, do not give away which option is right: the instructions above say what the feedback does instead.
- Without `correct_option` in the request, grade the answer on its own merits.
''';

/// What the model is told on a `contentQuestion` turn (#132) until the
/// teacher authors an instruction doc with that id — the seed text, and the
/// one request type that ships with a default. The other types have always
/// had a teacher-authored doc; this one is new, and a question about the
/// page must land as a plain `answer` from the first launch, not as an
/// exercise or a grade because the model was told nothing.
///
/// Rendered through the same tag replacement as a teacher doc, so
/// `{goal}`, `{subgoal}` and `{teachingTips}` name the page's subgoal.
const String defaultContentQuestionInstruction = '''
### CONTENT QUESTION

The student is reading the lesson page given in `content` (its title in `content_title`) and asks a question about it. The page belongs to the subgoal "{subgoal}" of the goal "{goal}".
Answer from the page, quoting it where that helps. If the page does not answer the question, say so and answer briefly anyway.
Do not start an exercise, do not grade, do not ask a follow-up question.

### TEXT section

The answer, in markdown. Keep it short.

### META section (JSON)

{"type": "answer"}
''';

/// Type-specific instruction bodies that ship with the app, keyed by the
/// instruction doc id a teacher would author to replace them. Only consulted
/// when no doc with that id exists.
const Map<String, String> builtInInstructions = {
  'contentQuestion': defaultContentQuestionInstruction,
};

class InstructionGenerator {
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
    required String languageCode,
    List<LearningObjective> targetLOs = const [],
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
    Goal? subgoalOverride,
  }) async {
    final selectedRoot = goalSelection.selectedRoot;
    final selectedChild = goalSelection.selectedChild;
    if (selectedRoot == null || selectedChild == null) return '';

    final instructions = cachedInstructions.isNotEmpty
        ? cachedInstructions
        : await fetchInstructions();

    final typeString = _chatRequestTypeToString(type);

    String alwaysInclude = '';
    String typeSpecific = '';
    final root = goalSelection.preferredRoot ?? selectedRoot;
    // A warm-up review question (#102) is about an older subgoal of the same
    // root: `{subgoal}` and `{teachingTips}` then describe that one, so the
    // model writes and grades the question in its proper context.
    final subgoal =
        subgoalOverride ?? goalSelection.preferredChild ?? selectedChild;
    final alwaysIncludeSubgoal = subgoalOverride ?? selectedChild;
    for (final instruction in instructions) {
      if (instruction.id == typeString) {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            root,
            subgoal,
            targetLOs: targetLOs,
            goalScopeLOs: goalScopeLOs,
          );
          typeSpecific += '$processed\n';
        }
      } else if (instruction.id == 'alwaysInclude') {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            selectedRoot,
            alwaysIncludeSubgoal,
            targetLOs: targetLOs,
            goalScopeLOs: goalScopeLOs,
          );
          alwaysInclude += '$processed\n';
        }
      }
    }

    // A type the teacher has not written a doc for yet falls back to the
    // body that ships with the app, if there is one (#132).
    final builtIn = builtInInstructions[typeString];
    if (typeSpecific.isEmpty && builtIn != null) {
      final processed = _replaceTags(
        builtIn,
        root,
        subgoal,
        targetLOs: targetLOs,
        goalScopeLOs: goalScopeLOs,
      );
      typeSpecific = '$processed\n';
    }

    // The grader of a multiple-choice pick is told how to treat the answer
    // key (#197) whatever the teacher's `mcqAnswer` doc says.
    final answerKey = type == ChatRequestType.mcqAnswer
        ? '\n$answerKeyDirective'
        : '';

    // The language directive goes last, after the teacher-authored bodies it
    // has to override (#117).
    return '$envelopeContract\n$alwaysInclude$typeSpecific$answerKey'
        '\n${languageDirective(languageCode)}';
  }

  String _chatRequestTypeToString(ChatRequestType type) =>
      type.toString().split('.').last;

  String _replaceTags(
    String input,
    Goal goal,
    Goal subGoal, {
    required List<LearningObjective> targetLOs,
    required List<({String subgoalId, LearningObjective lo})> goalScopeLOs,
  }) {
    String output = input;
    final teachingTips = subGoal.teachingTips.join('\n');
    final replacements = {
      'goal': goal.title,
      'subgoal': subGoal.title,
      // `{teachingTips}` is the canonical name; `{suggestions}` is kept as
      // an alias for any teacher-authored instruction docs that haven't been
      // updated yet.
      'teachingTips': teachingTips,
      'suggestions': teachingTips,
      'targetLOs': _renderTargetLOs(targetLOs),
      'goalScopeLOs': _renderGoalScopeLOs(goalScopeLOs),
      // `{known concepts}` no longer expands to a real list — the LO model
      // replaces concept-scope fencing. Stale instruction docs that still
      // reference it resolve to an empty string.
      'known concepts': '',
    };
    for (final entry in replacements.entries) {
      final pattern = RegExp(
        r'\{\s*' + entry.key + r'\s*\}',
        caseSensitive: false,
      );
      output = output.replaceAll(pattern, entry.value);
    }
    return output;
  }

  String _renderTargetLOs(List<LearningObjective> los) {
    if (los.isEmpty) return '';
    return los
        .map((lo) => '- (${lo.kind.name}) ${lo.id}: ${lo.statement}')
        .join('\n');
  }

  String _renderGoalScopeLOs(
    List<({String subgoalId, LearningObjective lo})> entries,
  ) {
    if (entries.isEmpty) return '';
    return entries
        .map(
          (e) =>
              '- [${e.subgoalId}] (${e.lo.kind.name}) ${e.lo.id}: ${e.lo.statement}',
        )
        .join('\n');
  }
}
