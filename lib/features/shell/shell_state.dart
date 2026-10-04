import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which session mode the workspace is rendering.
enum SessionMode { explain, practice, playground }

/// Top-level sidebar destinations. Student sees the first four; teacher
/// additionally sees goals / lessonContent / students / milestones / reports.
/// `instructions` is a developer tool (tutor system-prompt editor) and is
/// only reachable when [developerToolsProvider] is true (issue #26).
/// `options` is the settings / maintenance panel pinned to the bottom of
/// the sidebar (issue #25). `milestones` is the grading-milestone editor
/// (#99): grade proposals are teacher-only, so it never shows to a student.
/// `puntenformule` is the grade formula document itself, shipped with the
/// app for every student to read (#129). `reports` is the class-wide report
/// run and review surface (#148) — grades, so teacher-only like
/// `milestones`. `questions` is the question bank (#185): every question the
/// tutor generated, for the teacher to review and hide the bad ones.
/// `classes` is the class list with each class's weekly lessons (#218), next
/// to `students`: the Students page picks a student's class from it.
///
/// `trophies` is the student's trophy case — "Prijzenkast" (#220): their
/// badges. Student-only like `myReports`: a teacher earns no badges, and
/// sees the whole set on the proof sheet under Options instead.
///
/// `myReports` is the other end of that surface (#151): the reports #150
/// released, as the student they belong to reads them. It is *not* a second
/// view of `reports` — it reads only the signed-in user's own `/uid`
/// partition of the published copies, so it carries no live score and
/// nothing unreleased. It is student-only: a teacher is not graded, so their
/// own list is always empty, and the class-wide run they do want is
/// `reports`.
enum Section {
  session,
  map,
  trophies,
  puntenformule,
  myReports,
  goals,
  lessonContent,
  questions,
  instructions,
  students,
  classes,
  milestones,
  reports,
  options,
}

/// Whether developer-only surfaces (the instructions editor, the developer
/// section of the options panel) are exposed in the shell. Defaults to
/// [kDebugMode]; overridden in tests.
final developerToolsProvider = Provider<bool>((_) => kDebugMode);

enum Role { student, teacher }

class Profile {
  const Profile({
    required this.name,
    required this.topic,
    required this.level,
    required this.xp,
    required this.xpNext,
    required this.streak,
    required this.role,
  });

  final String name;
  final String topic;
  final int level;
  final int xp;
  final int xpNext;
  final int streak;
  final Role role;

  bool get isTeacher => role == Role.teacher;

  double get xpFraction =>
      xpNext <= 0 ? 0 : (xp.clamp(0, xpNext) / xpNext).clamp(0.0, 1.0);
}

final modeProvider = StateProvider<SessionMode>((_) => SessionMode.explain);

final sectionProvider = StateProvider<Section>((_) => Section.session);

/// Streams the persisted `Progress` doc for a single goal id, used by the
/// ambient rim. autoDispose so a stream isn't held open after the active
/// child goal changes.
final _progressByGoalIdStreamProvider = StreamProvider.autoDispose
    .family<Progress?, String>((ref, goalId) {
      return ref.watch(progressServiceProvider).streamByGoalId(goalId);
    });

/// Aggregated session-progress signal driving the 2px ambient progress line
/// at the top of the workspace. Tracks the active child goal's persisted
/// progress (issue #11, option a) — same data the goal tile reads.
final ambientProgressProvider = Provider<double>((ref) {
  final goalId = ref.watch(goalSelectionProvider).activeChildGoal?.id;
  if (goalId == null) return 0.0;
  return ref
      .watch(_progressByGoalIdStreamProvider(goalId))
      .maybeWhen(
        data: (p) => (p?.progress ?? 0.0).clamp(0.0, 1.0),
        orElse: () => 0.0,
      );
});

// XP & level derivation — issue #9, option (a); curve flattened in #116;
// XP per oefening since #217.
//
// XP = oefeningen × [kXpPerOefening] + mastery XP. The oefeningen are the
// account's `oefeningCount`: one per question at its first graded answer,
// right or wrong, never for a follow-up, and it only goes up. Mastery XP is
// `Progress.progress` summed over every non-optional subgoal × a flat
// constant; it moves only when an LO crosses the mastery bar, and back down
// when one falls under it again. Before #217 that was the whole of XP, so a
// lesson spent on one hard LO showed no progress at all and the bar could
// run backwards. Every level is the same width, so the ramp never gets
// steeper. No new collection — mastery XP is derived, the counter rides on
// the account doc the conductor already writes on every graded answer.

/// XP a fully-completed non-optional subgoal is worth.
const int kXpPerSubgoal = 100;

/// XP every oefening is worth (#217), whatever the grade. At the 20–25
/// oefeningen of a lesson hour in the September baseline that is about one
/// level per lesson hour, before any mastery XP.
const int kXpPerOefening = 20;

/// Constant width of every level, in XP.
const int kXpPerLevel = 500;

/// The level at [totalXp] XP: level 1 from 0, one more every [kXpPerLevel].
int levelForXp(int totalXp) => 1 + (totalXp < 0 ? 0 : totalXp) ~/ kXpPerLevel;

/// The XP shown in the top bar: [xp] into [level], of [xpNext] for the
/// next one, and the two parts the total is made of — what the level-up
/// moment needs to tell an oefening's crossing from a mastery's (#217).
typedef XpState = ({
  int xp,
  int level,
  int xpNext,
  int oefeningCount,
  int masteryXp,
});

const XpState _defaultXpState = (
  xp: 0,
  level: 1,
  xpNext: kXpPerLevel,
  oefeningCount: 0,
  masteryXp: 0,
);

XpState _xpBreakdown({required int oefeningCount, required int masteryXp}) {
  final raw = oefeningCount * kXpPerOefening + masteryXp;
  final total = raw < 0 ? 0 : raw;
  return (
    xp: total % kXpPerLevel,
    level: levelForXp(total),
    xpNext: kXpPerLevel,
    oefeningCount: oefeningCount,
    masteryXp: masteryXp,
  );
}

/// The mastery part of the XP: `progress × kXpPerSubgoal` summed over the
/// non-optional subgoals, re-emitted on every progress poll.
final masteryXpProvider = StreamProvider<int>((ref) async* {
  // Only react to sign-in/sign-out, not to every poll-driven re-emission of
  // the account doc — Account has no `==` override, so each 5 s
  // accountServiceProvider tick is a "new" object and would otherwise
  // tear this provider down and flash the XP pill back to 0.
  final signedIn = ref.watch(accountServiceProvider.select((a) => a != null));
  if (!signedIn) {
    yield 0;
    return;
  }
  final subgoals = (await ref.watch(goalsServiceProvider).getAllGoalsOnce())
      .where((g) => g.parentId != null && !g.optional)
      .toList();
  if (subgoals.isEmpty) {
    yield 0;
    return;
  }
  final progressStream = ref.watch(progressServiceProvider).watchAll();
  await for (final progress in progressStream) {
    final byId = {for (final p in progress) p.goalID: p};
    yield subgoals
        .fold<double>(
          0.0,
          (acc, g) => acc + (byId[g.id]?.progress ?? 0.0) * kXpPerSubgoal,
        )
        .round();
  }
});

/// The signed-in student's `oefeningCount` (#217); 0 when signed out. An
/// int, so the account doc's 5 s poll only passes on a real change.
final oefeningCountProvider = Provider<int>(
  (ref) =>
      ref.watch(accountServiceProvider.select((a) => a?.oefeningCount ?? 0)),
);

/// XP and level: [oefeningCountProvider] × [kXpPerOefening] plus
/// [masteryXpProvider]. Loading until the mastery part has its first value;
/// after that a new count or a progress poll recomputes it in place, so the
/// pill never drops back to its default in between.
final xpStateProvider = Provider<AsyncValue<XpState>>((ref) {
  final oefeningCount = ref.watch(oefeningCountProvider);
  return ref
      .watch(masteryXpProvider)
      .whenData(
        (masteryXp) =>
            _xpBreakdown(oefeningCount: oefeningCount, masteryXp: masteryXp),
      );
});

/// Derived view of the signed-in user for the new shell. Reads name + role
/// from existing services and composes XP/level from [xpStateProvider].
final profileProvider = Provider<Profile>((ref) {
  final account = ref.watch(accountServiceProvider);
  final isTeacher = ref.watch(isTeacherProvider);
  final xpState = ref
      .watch(xpStateProvider)
      .maybeWhen(data: (s) => s, orElse: () => _defaultXpState);
  return Profile(
    name: account?.firstName ?? '',
    topic: account?.targetGoal ?? '',
    level: xpState.level,
    xp: xpState.xp,
    xpNext: xpState.xpNext,
    streak: account?.streakDays ?? 0,
    role: isTeacher ? Role.teacher : Role.student,
  );
});

extension SessionModeLabel on SessionMode {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (this) {
      case SessionMode.explain:
        return l.session_mode_explain;
      case SessionMode.practice:
        return l.session_mode_practice;
      case SessionMode.playground:
        return l.session_mode_playground;
    }
  }

  /// Whether the chat panel is shown alongside this mode.
  bool get showsChatPanel {
    switch (this) {
      case SessionMode.practice:
      case SessionMode.explain:
        return true;
      case SessionMode.playground:
        return false;
    }
  }
}

extension SectionLabel on Section {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (this) {
      case Section.session:
        return l.sidebar_section_session;
      case Section.map:
        return l.sidebar_section_map;
      case Section.trophies:
        return l.sidebar_section_trophies;
      case Section.puntenformule:
        return l.sidebar_section_puntenformule;
      case Section.myReports:
        return l.sidebar_section_myReports;
      case Section.goals:
        return l.sidebar_section_goals;
      case Section.lessonContent:
        return l.sidebar_section_lessonContent;
      case Section.questions:
        return l.sidebar_section_questions;
      case Section.instructions:
        return l.sidebar_section_instructions;
      case Section.students:
        return l.sidebar_section_students;
      case Section.classes:
        return l.sidebar_section_classes;
      case Section.milestones:
        return l.sidebar_section_milestones;
      case Section.reports:
        return l.sidebar_section_reports;
      case Section.options:
        return l.sidebar_section_options;
    }
  }

  bool get isTeacherOnly {
    switch (this) {
      case Section.goals:
      case Section.lessonContent:
      case Section.questions:
      case Section.instructions:
      case Section.students:
      case Section.classes:
      case Section.milestones:
      case Section.reports:
        return true;
      case Section.session:
      case Section.map:
      case Section.trophies:
      case Section.puntenformule:
      case Section.myReports:
      case Section.options:
        return false;
    }
  }

  /// Sections a teacher does not get — the mirror of [isTeacherOnly].
  ///
  /// [Section.myReports] (#151): it lists the signed-in user's own published
  /// reports, and a teacher is never graded, so for them it is an empty page
  /// next to the class-wide [Section.reports] they actually want. And
  /// [Section.trophies] (#220): a teacher earns no badges; the proof sheet
  /// under Options shows them the set. Neither costs the teacher's rail an
  /// entry (#156).
  bool get isStudentOnly =>
      this == Section.myReports || this == Section.trophies;

  /// Sections that are hidden unless [developerToolsProvider] is true.
  bool get isDeveloperOnly => this == Section.instructions;
}
