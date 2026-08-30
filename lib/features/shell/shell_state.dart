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

/// Top-level sidebar destinations. Student sees the first two; teacher
/// additionally sees goals / lessonContent / students. `instructions` is a
/// developer tool (tutor system-prompt editor) and is only reachable when
/// [developerToolsProvider] is true (issue #26).
enum Section { session, map, goals, lessonContent, instructions, students }

/// Whether developer-only surfaces (the instructions editor, the debug
/// dialog) are exposed in the shell. Defaults to [kDebugMode]; overridden in
/// tests.
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
final _progressByGoalIdStreamProvider =
    StreamProvider.autoDispose.family<Progress?, String>((ref, goalId) {
  return ref.watch(progressServiceProvider).streamByGoalId(goalId);
});

/// Aggregated session-progress signal driving the 2px ambient progress line
/// at the top of the workspace. Tracks the active child goal's persisted
/// progress (issue #11, option a) — same data the goal tile reads.
final ambientProgressProvider = Provider<double>((ref) {
  final goalId = ref.watch(goalSelectionProvider).activeChildGoal?.id;
  if (goalId == null) return 0.0;
  return ref.watch(_progressByGoalIdStreamProvider(goalId)).maybeWhen(
        data: (p) => (p?.progress ?? 0.0).clamp(0.0, 1.0),
        orElse: () => 0.0,
      );
});

// XP & level derivation — issue #9, option (a).
//
// XP is derived from `Progress.progress` summed over every non-optional
// subgoal × a flat constant. Level steps are a gentle linear ramp
// (xpNext = 1500 * level). No new collection, no migration.

const int _xpPerSubgoal = 100;
int _xpNextFor(int level) => 1500 * level;

typedef XpState = ({int xp, int level, int xpNext});

const XpState _defaultXpState = (xp: 0, level: 1, xpNext: 1500);

XpState _xpBreakdown(int totalXp) {
  var level = 1;
  var remaining = totalXp;
  while (remaining >= _xpNextFor(level)) {
    remaining -= _xpNextFor(level);
    level += 1;
  }
  return (xp: remaining, level: level, xpNext: _xpNextFor(level));
}

final xpStateProvider = StreamProvider<XpState>((ref) async* {
  // Only react to sign-in/sign-out, not to every poll-driven re-emission of
  // the account doc — Account has no `==` override, so each 5 s
  // accountServiceProvider tick is a "new" object and would otherwise
  // tear this provider down and flash the XP pill back to 0.
  final signedIn =
      ref.watch(accountServiceProvider.select((a) => a != null));
  if (!signedIn) {
    yield _defaultXpState;
    return;
  }
  final subgoals = (await ref.watch(goalsServiceProvider).getAllGoalsOnce())
      .where((g) => g.parentId != null && !g.optional)
      .toList();
  if (subgoals.isEmpty) {
    yield _defaultXpState;
    return;
  }
  final progressStream = ref.watch(progressServiceProvider).watchAll();
  await for (final progress in progressStream) {
    final byId = {for (final p in progress) p.goalID: p};
    final total = subgoals
        .fold<double>(
          0.0,
          (acc, g) => acc + (byId[g.id]?.progress ?? 0.0) * _xpPerSubgoal,
        )
        .round();
    yield _xpBreakdown(total);
  }
});

/// Derived view of the signed-in user for the new shell. Reads name + role
/// from existing services and composes XP/level from [xpStateProvider].
final profileProvider = Provider<Profile>((ref) {
  final account = ref.watch(accountServiceProvider);
  final isTeacher = ref.watch(isTeacherProvider);
  final xpState = ref.watch(xpStateProvider).maybeWhen(
        data: (s) => s,
        orElse: () => _defaultXpState,
      );
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
      case Section.goals:
        return l.sidebar_section_goals;
      case Section.lessonContent:
        return l.sidebar_section_lessonContent;
      case Section.instructions:
        return l.sidebar_section_instructions;
      case Section.students:
        return l.sidebar_section_students;
    }
  }

  bool get isTeacherOnly {
    switch (this) {
      case Section.goals:
      case Section.lessonContent:
      case Section.instructions:
      case Section.students:
        return true;
      case Section.session:
      case Section.map:
        return false;
    }
  }

  /// Sections that are hidden unless [developerToolsProvider] is true.
  bool get isDeveloperOnly => this == Section.instructions;
}
