import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double sidebarWidth = 72;

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, this.onDebug});

  final VoidCallback? onDebug;

  static const _studentSections = [
    Section.session,
    Section.map,
  ];

  static const _teacherSections = [
    Section.goals,
    Section.lessonContent,
    Section.instructions,
    Section.students,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final selected = ref.watch(sectionProvider);

    return Container(
      width: sidebarWidth,
      color: AppColors.ink1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const _Logo(),
          const SizedBox(height: AppSpacing.xl),
          ..._studentSections.map(
            (s) => _SidebarItem(
              section: s,
              icon: _iconFor(s),
              active: selected == s,
              onTap: () => ref.read(sectionProvider.notifier).state = s,
            ),
          ),
          if (profile.isTeacher) ...[
            const SizedBox(height: AppSpacing.lg),
            const _SidebarHeader(label: 'Docent'),
            const SizedBox(height: AppSpacing.s),
            ..._teacherSections.map(
              (s) => _SidebarItem(
                section: s,
                icon: _iconFor(s),
                active: selected == s,
                onTap: () => ref.read(sectionProvider.notifier).state = s,
              ),
            ),
          ],
          const Spacer(),
          if (onDebug != null)
            _SidebarIconButton(
              tooltip: 'Debug',
              icon: Icons.bug_report_outlined,
              onTap: onDebug!,
            ),
          _SidebarIconButton(
            tooltip: 'Sign out',
            icon: Icons.logout,
            onTap: () =>
                ref.read(authServiceProvider.notifier).signOut(),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
      ),
    );
  }

  static IconData _iconFor(Section s) {
    switch (s) {
      case Section.session:
        return Icons.terminal_outlined;
      case Section.map:
        return Icons.insights_outlined;
      case Section.goals:
        return Icons.flag_outlined;
      case Section.lessonContent:
        return Icons.menu_book_outlined;
      case Section.instructions:
        return Icons.integration_instructions_outlined;
      case Section.students:
        return Icons.people_outline;
    }
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.accent, AppColors.accent2],
          ),
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        child: const Icon(
          Icons.auto_awesome_outlined,
          color: AppColors.ink0,
          size: 22,
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Text(
        label.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.fgFaint,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final Section section;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tinted = widget.active
        ? AppColors.ink2
        : (_hovering ? AppColors.ink2.withValues(alpha: 0.6) : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: widget.section.label,
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: Stack(
              children: [
                if (widget.active)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.m,
                  ),
                  decoration: BoxDecoration(
                    color: tinted,
                    borderRadius: BorderRadius.circular(AppRadius.inputLarge),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: widget.active
                          ? AppColors.fg
                          : AppColors.fgMute,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: AppColors.fgFaint),
        onPressed: onTap,
        splashRadius: 18,
      ),
    );
  }
}
