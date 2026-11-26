// Single source of truth for Cosmos container handles.

import 'package:ai_tutor_python/core/cosmos_client.dart';

const String _accountsContainer = 'accounts';
const String _progressContainer = 'progress';
const String _progressHistoryContainer = 'progress_history';
const String _statusReportsContainer = 'status_reports';
const String _goalsContainer = 'goals';
const String _instructionsContainer = 'instructions';
const String _configContainer = 'config';
const String _contentContainer = 'content';
const String _modulesContainer = 'modules';
const String _loBeliefsContainer = 'lo_beliefs';
const String _turnHistoryContainer = 'turn_history';
const String _playgroundFilesContainer = 'playground_files';
const String _milestonesContainer = 'milestones';
const String _gradeProposalsContainer = 'grade_proposals';
const String _reportsContainer = 'reports';
const String _questionsContainer = 'questions';
const String _translationsContainer = 'translations';
const String _turnContentContainer = 'turn_content';
const String _podiumContainer = 'podium';

/// What a student's session does in a container, for the roles of access
/// with the user's own sign-in (#306).
///
/// With that access Cosmos itself decides what a user may do, and a role
/// reaches a whole container: never a partition or a single document.
/// Teachers get [readWrite] on the whole database.
enum StudentAccess {
  /// A student's session writes here (create, upsert, replace, delete or a
  /// transactional batch): Cosmos DB Built-in Data Contributor.
  readWrite,

  /// A student's session only reads here; every write is in the teacher's
  /// pages: Cosmos DB Built-in Data Reader.
  read,

  /// A student's session never opens it: no role.
  none,
}

/// The role list per container (#306), worked out from the code: which
/// service opens the container, and where its writes are called from. A
/// write in a page that only a teacher sees (`Section.isTeacherOnly`) or
/// behind `isTeacherProvider` leaves a container at [StudentAccess.read];
/// one in the tutor, Practice, the Playground or Options makes it
/// [StudentAccess.readWrite].
///
/// The app does not read this: it is the list an administrator assigns the
/// roles from (README, "Access with the user's own sign-in").
/// `test/core/cosmos_student_access_test.dart` fails when a container above
/// has no entry here, or when the README's table or commands say otherwise.
/// A change that makes a student's session write a [StudentAccess.read]
/// container, or open a [StudentAccess.none] one, changes its entry here,
/// and then the README.
const Map<String, StudentAccess> kStudentAccess = {
  // `AccountService`: the profile at the first sign-in (`upsertAccount`),
  // then the streak, the calibration and `oefeningCount`, and the badges
  // after each oefening. Teacher-only (Students page): the KEY switch, the
  // class, a teacher badge, deleting an account.
  _accountsContainer: StudentAccess.readWrite,
  // `ProgressService.upsert` after a graded answer; a reset or an import in
  // Options deletes and writes.
  _progressContainer: StudentAccess.readWrite,
  // A sample per `ProgressService.upsert`; the import in Options.
  _progressHistoryContainer: StudentAccess.readWrite,
  // `ReportService.updateForCurrentChildGoal`, from the conductor.
  _statusReportsContainer: StudentAccess.readWrite,
  // `LoBeliefsService.upsert`, from the conductor; reset and import.
  _loBeliefsContainer: StudentAccess.readWrite,
  // `TurnHistoryService.append` and `appendAudit` per graded answer; the
  // reset deletes. Teacher-only: `acknowledgeAllFor` (Students page).
  _turnHistoryContainer: StudentAccess.readWrite,
  // `TurnContentService.record` after each oefening; the reset deletes.
  _turnContentContainer: StudentAccess.readWrite,
  // `PlaygroundFilesService.upsert`: a saved file, or a delete's tombstone.
  _playgroundFilesContainer: StudentAccess.readWrite,
  // Shared by all students. `QuestionBankService.recordAsked` creates a
  // question, `recordFirstAnswer` and `recordAnswer` count answers (and may
  // hide one). Teacher-only (Questions page): hide, show, delete.
  _questionsContainer: StudentAccess.readWrite,
  // Shared by all students. `ClassPodium.claim` creates a place (#338).
  _podiumContainer: StudentAccess.readWrite,
  // The tutor and the Leerpad read it. Writes: Goals and Lesson content.
  _goalsContainer: StudentAccess.read,
  // The tutor reads it. Writes: Instructions.
  _instructionsContainer: StudentAccess.read,
  // `global` (`GlobalConfigService`) and `classes` (`ClassesService
  // .readOnce`, the timetable). Writes: the school's model in Options
  // (`_GlobalModelCard`, behind `isTeacherProvider`) and Classes.
  _configContainer: StudentAccess.read,
  // Explain, the tutor and the reference read the lessons. Writes: Lesson
  // content.
  _contentContainer: StudentAccess.read,
  // The translations of lessons and goal texts. Writes: Goals and Lesson
  // content.
  _translationsContainer: StudentAccess.read,
  // The conductor reads them (`getMilestones`). Writes: Milestones.
  _milestonesContainer: StudentAccess.read,
  // My reports reads the student's own (`watchForUser`). Writes: Reports
  // (publish, republish).
  _reportsContainer: StudentAccess.read,
  // Only the teacher's Lesson content page reads and writes it.
  _modulesContainer: StudentAccess.none,
  // Only the teacher's Milestones and Reports pages.
  _gradeProposalsContainer: StudentAccess.none,
};

/// Constant partition-key values for the `/type` containers (`goals`,
/// `instructions`, `config`, `content`, `modules`, `milestones`, `podium`).
/// Each doc in those containers carries a `type` field with this exact value.
class CosmosPartitions {
  static const String goal = 'goal';
  static const String instruction = 'instruction';
  static const String config = 'config';
  static const String content = 'content';
  static const String module = 'module';
  static const String milestone = 'milestone';

  /// The class podium (#221): the one partition of the `podium` container
  /// (#338). Before, the second partition of `config`.
  static const String podium = 'podium';
}

class CosmosPaths {
  static CosmosClient get _client => CosmosClient.instance;

  /// `/uid` partition. One doc per user.
  static CosmosContainer accounts() => _client.container(_accountsContainer);

  /// `/uid` partition. Doc id `${uid}_${goalId}`. Now a derived cache of
  /// `progress: 0.0..1.0` aggregated from per-LO beliefs (see STUDENT_MODEL).
  static CosmosContainer progress() => _client.container(_progressContainer);

  /// `/uid` partition. One doc per progress sample, time-ordered. Time
  /// series for the teacher detail panel; not read in the student flow.
  static CosmosContainer progressHistory() =>
      _client.container(_progressHistoryContainer);

  /// `/uid` partition. Doc id `${uid}_${goalId}`. Flattened from the old
  /// `accounts/{uid}/status_reports/{goalId}` subcollection.
  static CosmosContainer statusReports() =>
      _client.container(_statusReportsContainer);

  /// `/type` partition (always `"goal"`). Single logical partition shared by
  /// all users — tree is small.
  static CosmosContainer goals() => _client.container(_goalsContainer);

  /// `/type` partition (always `"instruction"`). Single logical partition.
  static CosmosContainer instructions() =>
      _client.container(_instructionsContainer);

  /// `/type` partition (`"config"`). Two docs, `global` (the school
  /// settings) and `classes` (the classes and their lessons, #218). Students
  /// only read it: the class podium, which they write, has its own container
  /// since #338 ([podium]). An older deployment still has the podium's docs
  /// here, in the partition `"podium"`, until the teacher removes them after
  /// `tooling/badges/podium_copy.py` copied them over.
  static CosmosContainer config() => _client.container(_configContainer);

  /// `/type` partition (always `"content"`). One doc per authored
  /// explanation block; referenced from `Goal.contentId`.
  static CosmosContainer content() => _client.container(_contentContainer);

  /// `/type` partition (always `"module"`). Top-level grouping for goals;
  /// v1 has a single bootstrapped doc.
  static CosmosContainer modules() => _client.container(_modulesContainer);

  /// `/uid` partition. One doc per `(uid, subgoalId, loId)` Beta belief.
  /// Source of truth for student mastery state per STUDENT_MODEL.
  static CosmosContainer loBeliefs() => _client.container(_loBeliefsContainer);

  /// `/uid` partition. Append-only audit trail; one doc per graded turn
  /// per CONDUCTOR_POLICY 8.1. Consumed by debug surfaces only.
  static CosmosContainer turnHistory() =>
      _client.container(_turnHistoryContainer);

  /// `/uid` partition. One doc per saved playground file. Doc id
  /// `${uid}_${name}`; a deleted file stays behind as a tombstone so the
  /// delete reaches the student's other machines (#31).
  static CosmosContainer playgroundFiles() =>
      _client.container(_playgroundFilesContainer);

  /// `/type` partition (always `"milestone"`). One doc per grading
  /// milestone: the LOs expected by a report date with their Angoff split
  /// (#99, PUNTENFORMULE §2.1). Teacher-edited, a handful per year.
  static CosmosContainer milestones() =>
      _client.container(_milestonesContainer);

  /// `/uid` partition. Doc id `${uid}_${milestoneId}`: the computed grade
  /// proposal for one student on one milestone, its AI-written
  /// justification and the teacher's sign-off (#99). Teacher-only; the
  /// student app never reads it.
  static CosmosContainer gradeProposals() =>
      _client.container(_gradeProposalsContainer);

  /// `/uid` partition. Doc id `${uid}_${milestoneId}`: the published report
  /// of one student on one milestone — the frozen, student-facing copy of a
  /// signed-off grade proposal, written by the teacher's per-milestone
  /// release action (#150). The only grading container a student reads, and
  /// only their own partition of it.
  static CosmosContainer reports() => _client.container(_reportsContainer);

  /// `/subgoalId` partition. The question bank (#185): one doc per question
  /// the tutor generated, doc id `${subgoalId}_${contentHash}`, so the same
  /// generation lands on the same doc. Partitioned by subgoal because every
  /// student-side read and write names exactly one: storing a question,
  /// counting an answer, and (#186) finding the questions that fit a plan
  /// are point reads or single-partition queries. Only the teacher's
  /// Questions page fans out across partitions.
  static CosmosContainer questions() => _client.container(_questionsContainer);

  /// `/language` partition. Translations of lessons and goal texts (#206):
  /// doc id `content_${contentId}` (a lesson's `title` + `body`) or
  /// `goal_${goalId}` (a goal's `title` + `description`), one doc per
  /// language. Dutch is the source language and has no docs here: it stays
  /// in `content` and `goals`. Partitioned by language so a student fetches
  /// only the language they read in — and nothing when that is Dutch.
  static CosmosContainer translations() =>
      _client.container(_translationsContainer);

  /// `/uid` partition. What the student saw, answered and was told on each
  /// graded turn (#228): one doc per `turn_history` doc, with its id — the
  /// question, the answer, the feedback, the grader's signals before the
  /// scope check with a reason per dropped one, and the context. Expires at
  /// the end of the school year: every doc carries a `ttl`, the container
  /// has `defaultTtl: -1`. Written best-effort after the oefening; read by
  /// the teacher's tooling (`evaluate.py trace`).
  static CosmosContainer turnContent() =>
      _client.container(_turnContentContainer);

  /// `/type` partition (always `"podium"`). The class podium (#221): three
  /// docs per class and subgoal at most, `podium_{class}_{subgoal}_{1|2|3}`
  /// (`CosmosDocId.podium`), each claimed with a `create` that never
  /// overwrites, with the student's uid and nothing else about them. Its
  /// own container (#338), not a partition of `config`: with the user's own
  /// sign-in (#306) a role reaches a whole container, so students can write
  /// here and only read `config`.
  static CosmosContainer podium() => _client.container(_podiumContainer);
}
