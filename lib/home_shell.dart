import 'package:ai_tutor_python/data/account/account_providers.dart';
import 'package:ai_tutor_python/data/role/role_provider.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'features/dashboard/dashboard.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final accountAsync = ref.watch(myAccountProviderFuture);
    final isTeacherAsync = ref.watch(isTeacherProviderFuture(user.uid));

    // Title (same behavior you had)
    final titleText = accountAsync.maybeWhen(
      data: (acc) {
        final fallback =
            user.displayName?.split(' ').first ?? user.email ?? 'user';
        return "Welcome back ${acc?.firstName ?? fallback}, let's learn!";
      },
      orElse: () => 'Welcome…',
    );

    // Who can see the Goals Editor?
    final isTeacher = isTeacherAsync.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );

    // Build destinations based on permissions
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      if (isTeacher)
        const NavigationRailDestination(
          icon: Icon(Icons.flag_outlined),
          selectedIcon: Icon(Icons.flag),
          label: Text('Goals'),
        ),
    ];

    // Clamp index if teacher flag changes (e.g., on first load)
    final maxIndex = destinations.length - 1;
    if (_selectedIndex > maxIndex) _selectedIndex = 0;

    // Pick the current page
    Widget page;
    if (_selectedIndex == 0) {
      page = const Dashboard();
    } else {
      // index 1 only exists when isTeacher is true
      page = const GoalsPage();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
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
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.selected,
            leading: const SizedBox(height: 8),
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ],
      ),
    );
  }
}
