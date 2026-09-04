import 'dart:async';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/instructions/instructions_editor_page.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/milestones/milestones_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:ai_tutor_python/widgets/update_status.dart';
import 'package:ai_tutor_python/widgets/whats_new_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // Fire and forget: `start()` handles every failure itself and returns
    // immediately on a build that does not check by itself (#47), so the
    // first frame never waits on the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(updateControllerProvider.notifier).start());
      // The other end of the same flow (#119): whatever the *previous* build
      // stashed on its way into the installer. Also fire-and-forget — it only
      // reads a preference, and a launch never waits on it.
      unawaited(ref.read(whatsNewControllerProvider.notifier).load());
    });
  }

  @override
  Widget build(BuildContext context) {
    // The only place an update is offered — as a strip of chrome that waits,
    // not a modal that announces (#48). Everything else about the flow —
    // deciding, downloading, hashing, launching — lives in the controller,
    // and `apply()` is reachable only from the bar's own button.
    final offering = ref.watch(
      updateControllerProvider.select((s) => s.isOffering),
    );

    final profile = ref.watch(profileProvider);
    final section = ref.watch(sectionProvider);
    final devTools = ref.watch(developerToolsProvider);

    // If a teacher-only section is active but the user is not a teacher (or
    // a developer-only section without developer tools), bounce back to the
    // default section. Schedule the state mutation for after this build to
    // keep Riverpod happy.
    if ((section.isTeacherOnly && !profile.isTeacher) ||
        (section.isDeveloperOnly && !devTools)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sectionProvider.notifier).state = Section.session;
      });
    }

    return Scaffold(
      backgroundColor: AppColors.ink0,
      body: Column(
        children: [
          // Above the sidebar as well as the content: this is the app telling
          // the student something, not one page's business.
          if (offering) const UpdateOfferBar(),
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    const Sidebar(),
                    Expanded(
                      child: Column(
                        children: [
                          const TopBar(),
                          Expanded(child: _bodyFor(section)),
                        ],
                      ),
                    ),
                  ],
                ),
                const GoalSplashOverlay(),
                const LevelUpOverlay(),
                // Last, so a launch that has news to tell puts it in front of
                // anything else that happens to be up (#119).
                const WhatsNewOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyFor(Section section) {
    switch (section) {
      case Section.session:
        return const SessionView();
      case Section.map:
        return const LeerpadPage();
      case Section.goals:
        return const GoalsPage();
      case Section.lessonContent:
        return const LessonContentPage();
      case Section.instructions:
        return const InstructionsEditorPage();
      case Section.students:
        return const AccountsPage();
      case Section.milestones:
        return const MilestonesPage();
      case Section.options:
        return const OptionsPage();
    }
  }
}
