import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/features/progress/student_progress_list.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/instructions/instructions_editor_page.dart';
import 'package:ai_tutor_python/widgets/goal_crumb_in_app_bar.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:ai_tutor_python/widgets/multi_value_listenable_builder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'version.dart';
import 'features/dashboard/dashboard.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Uncomment the following line to enable update checking on startup
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MultiValueListenableBuilder(
          listenables: [
            DataService.role.isTeacher,
            DataService.account.currentAccount,
          ],
          builder: (context, values) {
            final isTeacher = values[0] as bool;
            final currentAccount = values[1] as Account?;

            // Title (same behavior you had)
            final titleText = currentAccount != null
                ? "Welcome back ${currentAccount.firstName}, let's learn!"
                : 'Welcome…';

            // Build destinations based on permissions
            final destinations = <NavigationRailDestination>[
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.flag_outlined),
                selectedIcon: Icon(Icons.flag),
                label: Text('Progress'),
              ),
              if (isTeacher)
                const NavigationRailDestination(
                  icon: Icon(Icons.flag_outlined),
                  selectedIcon: Icon(Icons.flag),
                  label: Text('Goals'),
                ),
              if (isTeacher)
                const NavigationRailDestination(
                  icon: Icon(Icons.integration_instructions_outlined),
                  selectedIcon: Icon(Icons.integration_instructions),
                  label: Text('Instructions'),
                ),
              if (isTeacher)
                const NavigationRailDestination(
                  icon: Icon(Icons.account_circle_outlined),
                  selectedIcon: Icon(Icons.account_circle),
                  label: Text('Accounts'),
                ),
            ];

            // Clamp index if teacher flag changes (e.g., on first load)
            final maxIndex = destinations.length - 1;
            if (_selectedIndex > maxIndex) _selectedIndex = 0;

            // Pick the current page
            final Widget page;
            if (_selectedIndex == 0) {
              page = const Dashboard();
            } else if (_selectedIndex == 1) {
              page = const StudentProgressList();
            } else if (isTeacher && _selectedIndex == 2) {
              page = const GoalsPage();
            } else if (isTeacher && _selectedIndex == 3) {
              page = const InstructionsEditorPage();
            } else if (_selectedIndex == 4 && isTeacher) {
              page = const AccountsPage();
            } else {
              page = const Center(child: Text('Page not found'));
            }

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 12,
                title: Row(
                  children: [
                    // Left: welcome text
                    Flexible(
                      flex: 2,
                      child: Text(titleText, overflow: TextOverflow.ellipsis),
                    ),
                    // Middle: goal/subgoal/progress
                    Expanded(
                      flex: 3,
                      child: Center(child: const GoalCrumbInAppBar()),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),

              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (i) =>
                        setState(() => _selectedIndex = i),
                    labelType: NavigationRailLabelType.selected,
                    leading: const SizedBox(height: 8),
                    destinations: destinations,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              ),
            );
          },
        ),
        const GoalSplashOverlay(),
      ],
    );
  }

  Future<void> checkForUpdate() async {
    final manifest = Uri.parse('https://ai-tutor-python.web.app/version.json');
    final info = await fetchUpdateInfo(manifest);
    if (info == null) return;

    if (isNewer(info.version, kAppVersion)) {
      // Show dialog before proceeding
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false, // user cannot tap outside to close
        builder: (context) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'A newer version (${info.version}) of the application is available. '
            'The update will now be installed. You can open it again in a moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Continue with update after pressing OK
      final file = await downloadToTemp(info.url);
      if (file == null) return;

      final ok = await verifySha256(file, info.sha256);
      if (!ok) {
        file.deleteSync();
        return;
      }

      await runInstallerAndExit(
        file,
        args: const ['/VERYSILENT', '/NORESTART'],
      );
    }
  }
}
