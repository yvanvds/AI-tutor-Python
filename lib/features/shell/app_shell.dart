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
import 'package:ai_tutor_python/version.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  Widget build(BuildContext context) {
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

  Future<void> _checkForUpdate() async {
    final manifest = Uri.parse(
      'https://yvanvds.github.io/AI-tutor-Python/version.json',
    );
    final info = await fetchUpdateInfo(manifest);
    if (info == null) return;
    if (!isNewer(info.version, kAppVersion)) return;
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.update_dialog_title),
          content: Text(l.update_dialog_message(info.version)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.update_dialog_ok),
            ),
          ],
        );
      },
    );

    final file = await downloadToTemp(info.url);
    if (file == null) return;
    final ok = await verifySha256(file, info.sha256);
    if (!ok) {
      file.deleteSync();
      return;
    }
    await runInstallerAndExit(file, args: const ['/VERYSILENT', '/NORESTART']);
  }
}
