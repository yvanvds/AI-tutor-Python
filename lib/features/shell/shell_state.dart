import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which session mode the workspace is rendering.
enum SessionMode { explain, practice, quiz, free }

/// Top-level sidebar destinations. Student sees the first two; teacher
/// additionally sees the last three.
enum Section { session, map, goals, instructions, students }

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

/// Aggregated session-progress signal driving the 2px ambient progress line
/// at the top of the workspace. Phase 6 wires this to real progression data;
/// for now it returns 0 so the line is invisible until there's signal.
final ambientProgressProvider = Provider<double>((_) => 0.0);

/// Derived view of the signed-in user for the new shell. Reads name + role
/// from existing services and supplies placeholder gamification fields until
/// `progression_service.dart` (Phase 6) wires them up for real.
final profileProvider = Provider<Profile>((ref) {
  final account = ref.watch(accountServiceProvider);
  final isTeacher = ref.watch(isTeacherProvider);
  return Profile(
    name: account?.firstName ?? '',
    topic: account?.targetGoal ?? '',
    level: 1,
    xp: 0,
    xpNext: 1500,
    streak: 0,
    role: isTeacher ? Role.teacher : Role.student,
  );
});

extension SessionModeLabel on SessionMode {
  String get label {
    switch (this) {
      case SessionMode.explain:
        return 'Uitleg';
      case SessionMode.practice:
        return 'Oefenen';
      case SessionMode.quiz:
        return 'Quiz';
      case SessionMode.free:
        return 'Vrij coderen';
    }
  }

  /// Whether the chat panel is shown alongside this mode.
  bool get showsChatPanel {
    switch (this) {
      case SessionMode.practice:
      case SessionMode.explain:
        return true;
      case SessionMode.quiz:
      case SessionMode.free:
        return false;
    }
  }
}

extension SectionLabel on Section {
  String get label {
    switch (this) {
      case Section.session:
        return 'Sessie';
      case Section.map:
        return 'Leerpad';
      case Section.goals:
        return 'Doelen';
      case Section.instructions:
        return 'Instructies';
      case Section.students:
        return 'Studenten';
    }
  }

  bool get isTeacherOnly {
    switch (this) {
      case Section.goals:
      case Section.instructions:
      case Section.students:
        return true;
      case Section.session:
      case Section.map:
        return false;
    }
  }
}
