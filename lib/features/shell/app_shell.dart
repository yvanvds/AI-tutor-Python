import 'dart:async';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/instructions/instructions_editor_page.dart';
import 'package:ai_tutor_python/features/lesson_content/lesson_content_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:ai_tutor_python/widgets/level_up_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Whether the offer dialog is on screen, so a rebuild that re-enters
  /// [UpdatePhase.available] cannot stack a second one.
  bool _offering = false;

  @override
  void initState() {
    super.initState();
    // Fire and forget: `start()` handles every failure itself and returns
    // immediately on a build that does not check by itself (#47), so the
    // first frame never waits on the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(updateControllerProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    // The only place an update is offered. Everything else about the flow —
    // deciding, downloading, hashing, launching — lives in the controller.
    ref.listen(updateControllerProvider.select((s) => s.release), (_, release) {
      if (release != null) _offerUpdate(release);
    });

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
      body: Stack(
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
      case Section.options:
        return const OptionsPage();
    }
  }

  /// Tells the student an update is waiting, and applies it once they close
  /// the dialog.
  ///
  /// The shell's whole remaining part in the flow: no fetching, no version
  /// comparison, no download, no `Process.start`. Failures below this point
  /// are handled by the controller and left on `UpdateState.message` for the
  /// About panel (#48), which is also where a real accept/decline choice and
  /// a progress indicator land.
  Future<void> _offerUpdate(UpdateInfo release) async {
    if (_offering || !mounted) return;
    _offering = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final l = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l.update_dialog_title),
            content: Text(l.update_dialog_message(release.version)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.update_dialog_ok),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      await ref.read(updateControllerProvider.notifier).apply();
    } finally {
      _offering = false;
    }
  }
}
